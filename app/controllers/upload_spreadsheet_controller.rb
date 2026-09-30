# frozen_string_literal: true

class UploadSpreadsheetController < ApplicationController
  before_action do
    authorize!(:create, Submission)
  end

  def create
    file = params[:file]

    return render_error(I18n.t(:spreadsheet_unsupported_file)) unless file.respond_to?(:tempfile)

    render json: Spreadsheets.parse(file.tempfile, filename: file.original_filename)
  rescue Spreadsheets::Error => e
    render_error(e.message)
  end

  private

  def render_error(message)
    render json: { error: message }, status: :unprocessable_content
  end
end
