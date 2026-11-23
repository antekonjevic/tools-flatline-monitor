require "test_helper"

class RunCheckJobTest < ActiveJob::TestCase
  test "runs the check" do
    check = create_check
    stub_request(:get, "https://example.com/").to_return(status: 200)

    RunCheckJob.perform_now(check)

    assert check.reload.up?
  end

  test "skips paused checks" do
    check = create_check
    check.pause!

    RunCheckJob.perform_now(check)

    assert_empty check.results
  end
end
