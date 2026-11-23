require "test_helper"

class WebsitesFilesControllerTest < ActionDispatch::IntegrationTest
  test "needs sign-in" do
    get websites_file_path(format: :json)
    assert_redirected_to new_session_path

    post websites_file_path
    assert_redirected_to new_session_path
  end

  test "downloads the export" do
    sign_in
    create_check(name: "Shop", url: "https://shop.example.com")

    get websites_file_path(format: :json)

    assert_response :success
    assert_match "attachment", response.headers["Content-Disposition"]
    assert_match(/flatline-websites-\d{4}-\d{2}-\d{2}\.json/, response.headers["Content-Disposition"])
    assert_equal "Shop", JSON.parse(response.body)["websites"].sole["name"]
  end

  test "imports a file" do
    sign_in
    create_check(name: "Shop", url: "https://shop.example.com")

    post websites_file_path, params: { file: upload([ { name: "Shop", url: "https://shop.example.com" },
                                                      { name: "Blog", url: "https://blog.example.com" } ]) }

    assert_redirected_to root_path
    assert_equal "Imported 2 websites: 1 added, 1 unchanged.", flash[:notice]
    assert_equal 2, Check.count
  end

  test "shows what's wrong with a file and imports nothing" do
    sign_in

    post websites_file_path, params: { file: upload([ { name: "", url: "nope" } ]) }

    assert_response :unprocessable_content
    assert_select ".form-errors li", minimum: 1
    assert_equal 0, Check.count
  end

  test "asks for a file when none is chosen" do
    sign_in

    post websites_file_path

    assert_redirected_to websites_file_path
  end

  private
    def upload(websites)
      file = Tempfile.new([ "websites", ".json" ])
      file.write({ flatline: 1, websites: websites }.to_json)
      file.rewind
      Rack::Test::UploadedFile.new(file.path, "application/json")
    end
end
