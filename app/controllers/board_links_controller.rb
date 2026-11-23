# The owner's view of the secret board link, and replacing it.
class BoardLinksController < ApplicationController
  def show
    @setting = Setting.instance
  end

  def update
    Setting.instance.regenerate_board_token
    redirect_to board_link_path, notice: "The board has a new link. The old one no longer works."
  end
end
