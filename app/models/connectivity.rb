require "net/http"

# The connection guard. Before a failed check counts against a website,
# Flatline makes sure it can reach the internet itself. If neither of these
# always-on services answers, the problem is on Flatline's side.
module Connectivity
  TARGETS = %w[
    https://1.1.1.1/cdn-cgi/trace
    https://www.google.com/generate_204
  ].freeze
  TIMEOUT = 5 # seconds

  def self.online?
    TARGETS.any? { |target| reachable?(target) }
  end

  # Any HTTP answer at all proves the connection works.
  def self.reachable?(url)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
      open_timeout: TIMEOUT, read_timeout: TIMEOUT, ssl_timeout: TIMEOUT, write_timeout: TIMEOUT) do |http|
      http.head(uri.request_uri, "User-Agent" => Flatline::USER_AGENT)
    end
    true
  rescue StandardError
    false
  end
end
