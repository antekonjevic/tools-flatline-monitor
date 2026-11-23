require "test_helper"

class ThemeTest < ActionDispatch::IntegrationTest
  test "follows the device until a theme is chosen" do
    get new_session_path

    assert_select "html[data-theme]", count: 0
    assert_select "meta[name=color-scheme][content=?]", "light dark"
    assert_select ".theme-option[aria-pressed=true]", count: 1
    assert_select ".theme-option[aria-pressed=true][title=?]", "Match device"
  end

  test "renders the chosen theme from the first paint" do
    cookies[:theme] = "dark"
    get new_session_path

    assert_select "html[data-theme=dark]"
    assert_select "meta[name=color-scheme][content=dark]"
    assert_select ".theme-option[aria-pressed=true][title=Dark]"
  end

  test "ignores a theme it doesn't know" do
    cookies[:theme] = "neon\" onload=\"alert(1)"
    get new_session_path

    assert_select "html[data-theme]", count: 0
    assert_select "meta[name=color-scheme][content=?]", "light dark"
  end

  test "the board has the theme switch but still no forms" do
    cookies[:theme] = "light"
    get board_path(token: Setting.instance.board_token)

    assert_select "html[data-theme=light]"
    assert_select ".theme-switch"
    assert_select "form", count: 0
  end
end
