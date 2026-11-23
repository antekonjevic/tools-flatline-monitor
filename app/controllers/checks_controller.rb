class ChecksController < ApplicationController
  before_action :set_check, only: %i[show edit update destroy]

  def index
    @checks = Check.in_overview_order(Check.all.to_a)
    @summaries = DailySummary.for_bars(@checks)
  end

  def show
    @summaries = DailySummary.for_bars([ @check ])
    @down_periods = @check.down_periods.where(started_at: Check::HISTORY.ago..)
      .or(@check.down_periods.ongoing).recent_first
    @results = @check.results.recent_first.limit(50)
  end

  def new
    @check = Check.new(interval_minutes: Check::DEFAULT_INTERVAL, failure_threshold: Check::DEFAULT_FAILURE_THRESHOLD)
  end

  def create
    @check = Check.new(check_params)

    if @check.save
      redirect_to @check, notice: "Flatline is now watching #{@check.name}."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @check.update(check_params)
      @check.reschedule_after_edit
      redirect_to @check, notice: "Changes saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @check.destroy!
    redirect_to root_path, notice: "#{@check.name} was removed.", status: :see_other
  end

  private
    def set_check
      @check = Check.find(params[:id])
    end

    def check_params
      params.expect(check: %i[name url group_name interval_minutes required_phrase failure_threshold])
    end
end
