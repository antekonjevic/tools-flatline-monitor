require "test_helper"

class BoardLinksControllerTest < ActionDispatch::IntegrationTest
  test "needs sign-in" do
    get board_link_path
    assert_redirected_to new_session_path

    patch board_link_path
    assert_redirected_to new_session_path
  end

  test "shows the secret link" do
    sign_in
    get board_link_path

    assert_select "input[value=?]", board_url(token: Setting.instance.board_token)
  end
end
