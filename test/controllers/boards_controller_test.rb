require "test_helper"

class BoardsControllerTest < ActionDispatch::IntegrationTest
  test "shows every website without a password" do
    create_check(name: "Shop", url: "https://shop.example.com/")

    get board_path(token: Setting.instance.board_token)

    assert_response :success
    assert_select ".check-name", "Shop"
    assert_select "a.check-url[href='https://shop.example.com/'][rel~=noreferrer]"
    assert_select ".bars"
    assert_select ".last-check"
    assert_select "form", count: 0
  end

  test "doesn't leak the link and stays out of search engines" do
    get board_path(token: Setting.instance.board_token)

    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_match "noindex", response.headers["X-Robots-Tag"]
    assert_select "meta[name=robots][content*=noindex]"
  end

  test "a wrong token is not found" do
    get board_path(token: "x" * 32)

    assert_response :not_found
    assert_select "h1", "This board link doesn't work"
    assert_select ".check-name", count: 0
  end

  test "the old link stops working once replaced" do
    old_token = Setting.instance.board_token
    sign_in
    patch board_link_path

    get board_path(token: old_token)
    assert_response :not_found

    get board_path(token: Setting.instance.board_token)
    assert_response :success
  end

  test "shows when Flatline is offline" do
    Setting.mark_offline!

    get board_path(token: Setting.instance.board_token)

    assert_select ".banner-offline"
  end
end
