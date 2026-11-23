require "test_helper"

class ProbeTest < ActiveSupport::TestCase
  test "a working page is up" do
    stub_request(:get, "https://example.com/").to_return(status: 200, body: "hello")

    result = Probe.new(url: "https://example.com/").call

    assert result.up?
    assert_equal 200, result.http_status
    assert_nil result.message
  end

  test "sends a User-Agent that names Flatline" do
    stub_request(:get, "https://example.com/").to_return(status: 200)

    Probe.new(url: "https://example.com/").call

    assert_requested :get, "https://example.com/", headers: { "User-Agent" => Flatline::USER_AGENT }
  end

  test "an HTTP error status is down" do
    stub_request(:get, "https://example.com/").to_return(status: [ 503, "Service Unavailable" ])

    result = Probe.new(url: "https://example.com/").call

    assert result.down?
    assert_equal "HTTP 503 Service Unavailable", result.message
    assert_equal 503, result.http_status
  end

  test "follows redirects" do
    stub_request(:get, "http://example.com/").to_return(status: 301, headers: { "Location" => "https://example.com/" })
    stub_request(:get, "https://example.com/").to_return(status: 302, headers: { "Location" => "/home" })
    stub_request(:get, "https://example.com/home").to_return(status: 200, body: "Welcome home")

    result = Probe.new(url: "http://example.com/", required_phrase: "Welcome").call

    assert result.up?
  end

  test "more than five redirects is down" do
    stub_request(:get, %r{https://example.com/\d+}).to_return do |request|
      { status: 302, headers: { "Location" => "/#{request.uri.path.delete("/").to_i + 1}" } }
    end

    result = Probe.new(url: "https://example.com/1").call

    assert result.down?
    assert_match "Too many redirects", result.message
    assert_requested :get, %r{https://example.com/\d+}, times: 6
  end

  test "a missing required phrase is down" do
    stub_request(:get, "https://example.com/").to_return(status: 200, body: "<h1>Error establishing a database connection</h1>")

    result = Probe.new(url: "https://example.com/", required_phrase: "Add to cart").call

    assert result.down?
    assert_equal "Required text “Add to cart” not found on the page", result.message
  end

  test "finds a non-ASCII required phrase" do
    stub_request(:get, "https://example.com/").to_return(status: 200, body: "<p>Dobrodošli</p>".b)

    assert Probe.new(url: "https://example.com/", required_phrase: "Dobrodošli").call.up?
  end

  test "network failures are down with a plain reason" do
    {
      SocketError.new("getaddrinfo: nodename nor servname provided") => "DNS lookup failed",
      Errno::ECONNREFUSED.new => "Connection refused",
      Errno::ECONNRESET.new => "Connection reset",
      Net::OpenTimeout.new => "No response within 30 seconds",
      OpenSSL::SSL::SSLError.new("SSL_connect returned=1 errno=0 state=error: certificate verify failed (certificate has expired)") => "Certificate expired",
      OpenSSL::SSL::SSLError.new("SSL_connect returned=1 errno=0 state=error: certificate verify failed (self-signed certificate)") => "Invalid certificate (self-signed certificate)"
    }.each do |error, message|
      WebMock.reset!
      stub_request(:get, "https://example.com/").to_raise(error)

      result = Probe.new(url: "https://example.com/").call

      assert result.down?, "#{error.class} should be down"
      assert_equal message, result.message
    end
  end

  test "a slow response is a warning" do
    stub_request(:get, "https://example.com/").to_return(status: 200)

    result = Probe.new(url: "https://example.com/", slow_after: -1).call

    assert result.warning?
    assert_match "Slow response", result.message
  end

  test "bugs in Flatline are raised, not blamed on the website" do
    stub_request(:get, "https://example.com/").to_raise(ArgumentError)

    assert_raises(ArgumentError) { Probe.new(url: "https://example.com/").call }
  end
end
