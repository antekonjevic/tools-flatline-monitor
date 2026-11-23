require "test_helper"

class WebsitesFileTest < ActiveSupport::TestCase
  def import(websites)
    WebsitesFile.new({ flatline: 1, websites: websites }.to_json).import
  end

  test "exports every website's settings" do
    create_check(name: "Shop", url: "https://shop.example.com", group_name: "Acme", interval_minutes: 15,
      required_phrase: "Add to cart", failure_threshold: 3)
    create_check(name: "Blog", url: "https://blog.example.com").pause!

    data = JSON.parse(WebsitesFile.export)

    assert_equal 1, data["flatline"]
    assert_equal [ "Shop", "Blog" ], data["websites"].map { it["name"] }
    assert_equal({ "name" => "Shop", "url" => "https://shop.example.com", "group" => "Acme", "interval_minutes" => 15,
      "required_text" => "Add to cart", "failures_before_down" => 3, "paused" => false }, data["websites"].first)
    assert data["websites"].last["paused"]
  end

  test "an export imports back unchanged" do
    create_check(name: "Shop", url: "https://shop.example.com", group_name: "Acme")
    create_check(name: "Blog", url: "https://blog.example.com").pause!

    result = WebsitesFile.new(WebsitesFile.export).import

    assert result.success?
    assert_equal 2, result.unchanged
    assert_equal 2, Check.count
    assert_no_enqueued_jobs
  end

  test "adds new websites with defaults and checks them" do
    result = nil
    assert_enqueued_jobs 1, only: RunCheckJob do
      result = import([ { name: "Shop", url: "shop.example.com" } ])
    end

    assert_equal 1, result.added
    check = Check.sole
    assert_equal "https://shop.example.com", check.url
    assert_equal Check::DEFAULT_INTERVAL, check.interval_minutes
    assert_equal Check::DEFAULT_FAILURE_THRESHOLD, check.failure_threshold
  end

  test "adds a paused website without checking it" do
    assert_no_enqueued_jobs do
      import([ { name: "Shop", url: "https://shop.example.com", paused: true } ])
    end

    assert Check.sole.paused?
  end

  test "updates websites matched by address and keeps what the file leaves out" do
    check = create_check(name: "Shop", url: "https://shop.example.com", group_name: "Acme", required_phrase: "Cart")

    result = import([ { name: "Acme shop", url: "https://shop.example.com", group: nil } ])

    assert_equal 1, result.updated
    check.reload
    assert_equal "Acme shop", check.name
    assert_nil check.group_name
    assert_equal "Cart", check.required_phrase
  end

  test "changing the required text checks again straight away" do
    create_check(url: "https://shop.example.com")

    assert_enqueued_jobs 1, only: RunCheckJob do
      import([ { url: "https://shop.example.com", required_text: "Add to cart" } ])
    end
  end

  test "pauses and resumes existing websites" do
    running = create_check(url: "https://a.example.com")
    resting = create_check(url: "https://b.example.com")
    resting.pause!

    import([ { url: "https://a.example.com", paused: true }, { url: "https://b.example.com", paused: false } ])

    assert running.reload.paused?
    assert resting.reload.pending?
  end

  test "leaves websites that aren't in the file alone" do
    create_check(url: "https://kept.example.com")

    import([ { name: "New", url: "https://new.example.com" } ])

    assert_equal 2, Check.count
  end

  test "changes nothing if any entry is invalid" do
    check = create_check(name: "Shop", url: "https://shop.example.com")

    result = import([
      { name: "Renamed", url: "https://shop.example.com" },
      { name: "Bad", url: "https://bad.example.com", interval_minutes: 7 },
      { url: "https://nameless.example.com" }
    ])

    assert_not result.success?
    assert_equal [ "Website 2 (Bad): Check interval must be 1, 5, 15 or 60 minutes.",
                   "Website 3: Name can't be blank." ], result.errors
    assert_equal "Shop", check.reload.name
    assert_equal 1, Check.count
  end

  test "rejects files that aren't exports" do
    assert_equal [ "This isn't a Flatline export: the file isn't valid JSON." ], WebsitesFile.new("nope").import.errors
    assert_match "no list of websites", WebsitesFile.new({ hello: 1 }.to_json).import.errors.sole
    assert_match "newer version", WebsitesFile.new({ flatline: 2, websites: [] }.to_json).import.errors.sole
  end

  test "rejects duplicate addresses, wrong types and missing addresses" do
    errors = import([
      { name: "A", url: "https://a.example.com" },
      { name: "A again", url: "a.example.com" },
      { name: 5, url: "https://b.example.com" },
      { name: "C", url: "https://c.example.com", paused: "yes" },
      { name: "D" },
      "just text"
    ]).errors

    assert_equal [
      "Website 2 (A again): https://a.example.com appears more than once in the file.",
      "Website 3: \"name\" must be text.",
      "Website 4 (C): \"paused\" must be true or false.",
      "Website 5 (D): the address (\"url\") is missing.",
      "Website 6: should be a set of settings, like the ones in an exported file."
    ], errors
  end

  test "accepts a plain list of websites" do
    result = WebsitesFile.new([ { name: "Shop", url: "https://shop.example.com" } ].to_json).import

    assert_equal 1, result.added
  end
end
