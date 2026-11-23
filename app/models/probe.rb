require "net/http"
require "openssl"

# Makes one HTTP GET request to a website and decides whether it is up, has a
# warning or is down. It knows nothing about the database; Check#run! records
# what it finds.
class Probe
  MAX_REDIRECTS = 5
  MAX_BODY_BYTES = 5.megabytes

  Result = Data.define(:outcome, :message, :http_status, :response_ms, :cert_expires_at) do
    def up? = outcome == "up"
    def warning? = outcome == "warning"
    def down? = outcome == "down"
  end

  class TooManyRedirects < StandardError; end
  class UnsupportedRedirect < StandardError; end
  class DeadlineExceeded < Timeout::Error; end

  # Everything that means "the website didn't answer properly". Any other
  # exception is a bug in Flatline, so it is raised instead of being blamed on
  # the website.
  FAILURES = [
    SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError,
    Net::HTTPBadResponse, Net::ProtocolError, Zlib::Error, URI::Error,
    TooManyRedirects, UnsupportedRedirect
  ].freeze

  def initialize(url:, required_phrase: nil, timeout: Check::TIMEOUT,
                 slow_after: Check::SLOW_RESPONSE, certificate_warning: Check::CERTIFICATE_WARNING)
    @url = url
    @required_phrase = required_phrase.presence
    @timeout = timeout.to_f
    @slow_after = slow_after.to_f
    @certificate_warning = certificate_warning
  end

  def call
    @started = monotonic_now
    @cert_expires_at = nil

    # Backstop in case a single step (such as a DNS lookup) ignores its own
    # timeout. Each request also gets the time that is left.
    Timeout.timeout(@timeout + 1, DeadlineExceeded) { follow(URI(@url)) }
  rescue *FAILURES => error
    result("down", describe(error))
  end

  private
    def follow(uri)
      redirects = 0

      loop do
        response, body = fetch(uri)

        if response.is_a?(Net::HTTPRedirection) && response["location"].present?
          raise TooManyRedirects if redirects >= MAX_REDIRECTS

          redirects += 1
          uri = URI.join(uri.to_s, response["location"].strip)
          raise UnsupportedRedirect, uri.to_s unless uri.is_a?(URI::HTTP) && uri.host.present?
        else
          return evaluate(response, body)
        end
      end
    end

    def fetch(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = http.read_timeout = http.ssl_timeout = http.write_timeout = remaining_time

      http.start do |connection|
        note_certificate(connection.peer_cert) if http.use_ssl?

        request = Net::HTTP::Get.new(uri, "User-Agent" => Flatline::USER_AGENT, "Accept" => "text/html,*/*;q=0.8")
        body = +""
        response = nil

        catch(:enough) do
          connection.request(request) do |res|
            response = res
            throw :enough unless read_body?(res)

            res.read_body do |chunk|
              body << chunk
              remaining_time
              throw :enough if body.bytesize >= MAX_BODY_BYTES
            end
          end
        end

        [ response, body ]
      end
    end

    def read_body?(response)
      @required_phrase && !response.is_a?(Net::HTTPRedirection) && response.code.to_i < 400
    end

    def evaluate(response, body)
      status = response.code.to_i

      if status >= 400
        result("down", "HTTP #{status} #{response.message}".strip, status)
      elsif @required_phrase && !text(body).include?(@required_phrase)
        result("down", "Required text “#{@required_phrase}” not found on the page", status)
      elsif (warnings = warnings_for).any?
        result("warning", warnings.join(" · "), status)
      else
        result("up", nil, status)
      end
    end

    def warnings_for
      warnings = []
      warnings << "Slow response (#{format("%.1f", elapsed)} s)" if elapsed > @slow_after
      if @cert_expires_at && @cert_expires_at < Time.current + @certificate_warning
        days = ((@cert_expires_at - Time.current) / 1.day).floor
        warnings << (days < 1 ? "Certificate expires within a day" : "Certificate expires in #{days} #{"day".pluralize(days)}")
      end
      warnings
    end

    def note_certificate(certificate)
      return unless certificate

      expires_at = certificate.not_after
      @cert_expires_at = [ @cert_expires_at, expires_at ].compact.min
    end

    def text(body)
      body.dup.force_encoding(Encoding::UTF_8).scrub
    end

    def describe(error)
      case error
      when TooManyRedirects then "Too many redirects (more than #{MAX_REDIRECTS})"
      when UnsupportedRedirect then "Redirected to an address that can't be checked"
      when Timeout::Error, Errno::ETIMEDOUT then "No response within #{@timeout.round} seconds"
      when SocketError then "DNS lookup failed"
      when Errno::ECONNREFUSED then "Connection refused"
      when Errno::ECONNRESET, EOFError then "Connection reset"
      when Errno::EHOSTUNREACH, Errno::ENETUNREACH then "Host unreachable"
      when OpenSSL::SSL::SSLError then describe_ssl(error)
      when Net::HTTPBadResponse, Net::ProtocolError, Zlib::Error then "Invalid HTTP response"
      when URI::Error then "Invalid address"
      else error.message.truncate(200)
      end
    end

    def describe_ssl(error)
      detail = error.message[/certificate verify failed \((.+?)\)/, 1]

      if error.message.include?("certificate has expired") then "Certificate expired"
      elsif error.message.include?("does not match") then "Invalid certificate (wrong host name)"
      elsif detail then "Invalid certificate (#{detail})"
      else "Secure connection failed"
      end
    end

    def result(outcome, message, http_status = nil)
      Result.new(outcome:, message:, http_status:, response_ms: (elapsed * 1000).round, cert_expires_at: @cert_expires_at)
    end

    def remaining_time
      left = @timeout - elapsed
      raise DeadlineExceeded if left <= 0
      left
    end

    def elapsed
      monotonic_now - @started
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
end
