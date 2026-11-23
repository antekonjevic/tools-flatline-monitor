ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    include ActiveJob::TestHelper

    def create_check(**attributes)
      check = Check.create!({ name: "Example", url: "https://example.com" }.merge(attributes))
      clear_enqueued_jobs
      check
    end

    def probe_result(outcome, message: nil, http_status: 200, response_ms: 120)
      Probe::Result.new(outcome:, message:, http_status:, response_ms:, cert_expires_at: nil)
    end

    def stub_connectivity(online:)
      Connectivity::TARGETS.each do |target|
        stub = stub_request(:head, target)
        online ? stub.to_return(status: 200) : stub.to_raise(SocketError)
      end
    end
  end
end

class ActionDispatch::IntegrationTest
  def sign_in
    post session_path, params: { password: Flatline::DEVELOPMENT_PASSWORD }
  end
end
