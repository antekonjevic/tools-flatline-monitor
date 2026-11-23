require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "admin pages need sign-in" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "signs in with the right password and returns to the page asked for" do
    check = create_check
    get check_path(check)

    post session_path, params: { password: Flatline::DEVELOPMENT_PASSWORD }

    assert_redirected_to check_path(check)
  end

  test "rejects the wrong password" do
    post session_path, params: { password: "nope" }

    assert_response :unprocessable_content
    get root_path
    assert_redirected_to new_session_path
  end

  test "signs out" do
    sign_in
    delete session_path

    get root_path
    assert_redirected_to new_session_path
  end

  test "uses the digest from the environment" do
    ENV["FLATLINE_PASSWORD_DIGEST"] = BCrypt::Password.create("correct horse battery", cost: BCrypt::Engine::MIN_COST)

    post session_path, params: { password: Flatline::DEVELOPMENT_PASSWORD }
    assert_response :unprocessable_content

    post session_path, params: { password: "correct horse battery" }
    assert_redirected_to root_path
  ensure
    ENV.delete("FLATLINE_PASSWORD_DIGEST")
  end

  test "changing the password ends existing sessions" do
    sign_in
    ENV["FLATLINE_PASSWORD_DIGEST"] = BCrypt::Password.create("a different password", cost: BCrypt::Engine::MIN_COST)

    get root_path
    assert_redirected_to new_session_path
  ensure
    ENV.delete("FLATLINE_PASSWORD_DIGEST")
  end
end
