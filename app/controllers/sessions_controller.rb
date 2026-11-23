class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: "Too many attempts. Try again in a few minutes." }

  def new
    redirect_to root_path if signed_in?
  end

  def create
    if Authentication.password_matches?(params[:password])
      return_to = sign_in
      redirect_to safe_return_path(return_to)
    else
      flash.now[:alert] = "That password isn't right."
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    sign_out
    redirect_to new_session_path, notice: "Signed out."
  end

  private
    def safe_return_path(path)
      path.is_a?(String) && path.start_with?("/") && !path.start_with?("//") ? path : root_path
    end
end
