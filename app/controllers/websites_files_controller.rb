# Import & export of every website's settings (see WebsitesFile).
class WebsitesFilesController < ApplicationController
  def show
    respond_to do |format|
      format.html { @count = Check.count }
      format.json do
        send_data WebsitesFile.export, filename: WebsitesFile.filename, type: :json, disposition: :attachment
      end
    end
  end

  def create
    file = params[:file]

    unless file.respond_to?(:read)
      return redirect_to websites_file_path, alert: "Choose a file to import."
    end

    @result = WebsitesFile.new(file.read(WebsitesFile::MAX_BYTES + 1)).import

    if @result.success?
      redirect_to root_path, notice: import_summary(@result)
    else
      @count = Check.count
      render :show, status: :unprocessable_content
    end
  end

  private
    def import_summary(result)
      return "The file has no websites in it, so nothing changed." if result.total.zero?

      parts = []
      parts << "#{result.added} added" if result.added.positive?
      parts << "#{result.updated} updated" if result.updated.positive?
      parts << "#{result.unchanged} unchanged" if result.unchanged.positive?
      "Imported #{helpers.pluralize(result.total, "website")}: #{parts.join(", ")}."
    end
end
