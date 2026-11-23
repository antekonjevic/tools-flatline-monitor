# The read-only board behind the secret link. No sign-in needed.
class BoardsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_privacy_headers
  before_action :require_valid_token

  layout "board"

  def show
    @checks = Check.in_overview_order(Check.all.to_a)
    @summaries = DailySummary.for_bars(@checks)
  end

  private
    # Don't leak the secret link to the websites on the board. (Every page
    # also gets X-Robots-Tag: noindex from ApplicationController.)
    def set_privacy_headers
      response.set_header("Referrer-Policy", "no-referrer")
    end

    # A replaced or mistyped link gets a page that says so, not a blank one.
    def require_valid_token
      render :not_found, status: :not_found unless Setting.board_token_matches?(params[:token])
    end
end
