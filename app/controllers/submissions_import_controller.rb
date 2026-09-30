# frozen_string_literal: true

# Creates one submission for every row of an imported spreadsheet. The rows are prepared in the browser
# (app/javascript/template_builder/import_list.vue) from the result of UploadSpreadsheetController.
class SubmissionsImportController < ApplicationController
  load_and_authorize_resource :template

  before_action do
    authorize!(:create, Submission)
  end

  SUBMITTER_KEYS = %w[uuid role name email phone external_id].freeze

  def create
    return redirect_to template_path(@template), alert: I18n.t('template_has_been_archived') if @template.archived_at?

    save_template_message if params[:save_message] == '1' && can?(:update, @template)

    [params.delete(:subject), params.delete(:body)] if params[:is_custom_message] != '1'

    submissions = create_submissions(build_submissions_attrs)

    WebhookUrls.enqueue_events(submissions, 'submission.created')

    Submissions.send_signature_requests(submissions, delay: 0)

    SearchEntries.enqueue_reindex(submissions)

    redirect_to template_path(@template), notice: I18n.t('new_recipients_have_been_added')
  rescue Submissions::CreateFromSubmitters::BaseError, Submitters::NormalizeValues::BaseError,
         DownloadUtils::UnableToDownload, JSON::ParserError => e
    render turbo_stream: turbo_stream.replace(:submitters_error, partial: 'submissions/error',
                                                                 locals: { error: e.message }),
           status: :unprocessable_content
  end

  private

  def create_submissions(submissions_attrs)
    ApplicationRecord.transaction do
      Submissions.create_from_submitters(template: @template,
                                         user: current_user,
                                         source: :bulk,
                                         submitters_order: params[:preserve_order] == '1' ? 'preserved' : 'random',
                                         submissions_attrs:,
                                         params: params.merge('send_completed_email' => true))
    end
  end

  # Only the recipients and the values to prefill are taken from the browser, and only for roles of the template.
  def build_submissions_attrs
    rows = JSON.parse(params[:submissions_json].to_s)

    raise JSON::ParserError, I18n.t(:spreadsheet_is_empty) unless rows.is_a?(Array) && rows.present?

    if rows.size > Spreadsheets::MAX_ROWS
      raise JSON::ParserError, I18n.t(:spreadsheet_too_many_rows, count: Spreadsheets::MAX_ROWS)
    end

    submissions_attrs = rows.filter_map { |row| build_submission_attrs(row) }

    raise JSON::ParserError, I18n.t(:spreadsheet_is_empty) if submissions_attrs.blank?

    Submissions::NormalizeParamUtils.normalize_submissions_params!(submissions_attrs, @template, purpose: :bulk).first
  end

  def build_submission_attrs(row)
    submitters = Array.wrap(row.is_a?(Hash) ? row['submitters'] : nil).filter_map { |item| build_submitter_attrs(item) }

    { submitters: }.with_indifferent_access if submitters.present?
  end

  def build_submitter_attrs(item)
    return unless item.is_a?(Hash) && template_submitter_uuids.include?(item['uuid'])

    attrs = item.slice(*SUBMITTER_KEYS).transform_values { |value| value.to_s.strip.presence }.compact
    attrs['uuid'] = item['uuid']
    attrs['fields'] = Array.wrap(item['fields']).filter_map { |field| build_field_attrs(field) }

    attrs
  end

  def build_field_attrs(field)
    return unless field.is_a?(Hash) && field['name'].present? && field['default_value'].present?

    { 'name' => field['name'].to_s, 'default_value' => field['default_value'].to_s, 'readonly' => true }
  end

  def template_submitter_uuids
    @template_submitter_uuids ||= @template.submitters.pluck('uuid')
  end

  def save_template_message
    @template.preferences['request_email_subject'] = params[:subject] if params[:subject].present?
    @template.preferences['request_email_body'] = params[:body] if params[:body].present?

    @template.save!
  end
end
