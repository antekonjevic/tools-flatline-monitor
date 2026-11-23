require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "board token is 32 characters" do
    assert_equal 32, Setting.instance.board_token.length
  end

  test "board token matches only exactly" do
    token = Setting.instance.board_token

    assert Setting.board_token_matches?(token)
    assert_not Setting.board_token_matches?(token.chop)
    assert_not Setting.board_token_matches?("")
    assert_not Setting.board_token_matches?(nil)
  end

  test "replacing the token invalidates the old one" do
    old = Setting.instance.board_token
    Setting.instance.regenerate_board_token

    assert_not Setting.board_token_matches?(old)
  end

  test "checking has stalled when the scheduler hasn't run" do
    create_check
    Setting.tick!(10.minutes.ago)

    assert Setting.instance.checking_stalled?

    Setting.tick!
    assert_not Setting.instance.checking_stalled?
  end
end
