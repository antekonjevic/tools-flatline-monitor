# Pausing is for planned maintenance: the downtime doesn't count.
class PausesController < ApplicationController
  before_action :set_check

  def create
    @check.pause!
    redirect_back_or_to @check, notice: "#{@check.name} is paused."
  end

  def destroy
    @check.resume!
    redirect_back_or_to @check, notice: "#{@check.name} is being watched again.", status: :see_other
  end

  private
    def set_check
      @check = Check.find(params[:check_id])
    end
end
