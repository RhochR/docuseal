# frozen_string_literal: true

describe 'Bulk send from a spreadsheet' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:folder) { create(:template_folder, account:) }
  let(:template) { create(:template, account:, author: user, folder:) }
  let(:submitter_uuid) { template.submitters.first['uuid'] }

  before { sign_in(user) }

  def csv_upload(content, filename = 'people.csv')
    Rack::Test::UploadedFile.new(StringIO.new(content), 'text/csv', original_filename: filename)
  end

  def prefill(value)
    [{ name: 'First Name', default_value: value, readonly: true }]
  end

  def row(email, name: nil, fields: [])
    { submitters: [{ uuid: submitter_uuid, role: 'First Party', email:, name:, fields: }.compact] }
  end

  describe 'POST /upload_spreadsheet' do
    it 'returns the sheets of a CSV file as JSON' do
      post upload_spreadsheet_path, params: { file: csv_upload("Email,Name\na@example.com,Ann\n") }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([['people', [%w[Email Name], %w[a@example.com Ann]]]])
    end

    it 'returns an error as JSON for unsupported files' do
      post upload_spreadsheet_path, params: { file: csv_upload('%PDF', 'people.pdf') }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to include('Unsupported file')
    end

    it 'returns an error as JSON without a file' do
      post upload_spreadsheet_path

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to be_present
    end

    it 'requires a signed in user' do
      sign_out(user)

      post upload_spreadsheet_path, params: { file: csv_upload("Email\na@example.com\n") }

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe 'POST /templates/:id/submissions_import' do
    let(:name_field) { template.fields.find { |f| f['name'] == 'First Name' } }

    def import(rows, **params)
      post template_submissions_import_path(template), params: { submissions_json: rows.to_json, **params }
    end

    it 'creates one submission per row with the values prefilled and read only' do
      rows = [row('ann@example.com', name: 'Ann', fields: prefill('Ann')),
              row('bob@example.com', name: 'Bob', fields: prefill('Bob'))]

      expect { import(rows) }.to change(Submission, :count).by(2)

      expect(response).to redirect_to(template_path(template))

      submissions = template.submissions.order(:id)

      expect(submissions.map(&:source)).to eq(%w[bulk bulk])
      expect(submissions.map { |s| s.submitters.first.email }).to eq(%w[ann@example.com bob@example.com])
      expect(submissions.map { |s| s.submitters.first.name }).to eq(%w[Ann Bob])
      expect(submissions.map { |s| s.submitters.first.values[name_field['uuid']] }).to eq(%w[Ann Bob])
      expect(submissions.first.template_fields.find { |f| f['uuid'] == name_field['uuid'] }['readonly']).to be(true)
    end

    it 'sends the invitation emails one second apart when asked to' do
      Sidekiq::Testing.fake! if defined?(Sidekiq::Testing)

      expect { import([row('ann@example.com'), row('bob@example.com')], send_email: '1') }
        .to change(SendSubmitterInvitationEmailJob.jobs, :size).by(2)
    end

    it 'ignores roles that are not part of the template and unknown parameters' do
      valid = { uuid: submitter_uuid, email: 'ann@example.com', completed: true, values: { 'x' => 'y' } }
      rows = [{ submitters: [{ uuid: SecureRandom.uuid, email: 'evil@example.com' }] }, { submitters: [valid] }]

      expect { import(rows) }.to change(Submission, :count).by(1)

      submitter = template.submissions.last.submitters.first

      expect(submitter.email).to eq('ann@example.com')
      expect(submitter.completed_at).to be_nil
    end

    it 'creates nothing when a row is invalid' do
      rows = [row('ann@example.com'),
              row('bob@example.com', fields: [{ name: 'Nonexistent field', default_value: 'x', readonly: true }])]

      expect { import(rows) }.not_to change(Submission, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects an empty list and invalid JSON' do
      expect { import([]) }.not_to change(Submission, :count)
      expect(response).to have_http_status(:unprocessable_content)

      post template_submissions_import_path(template), params: { submissions_json: 'not json' }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects lists that are too long' do
      stub_const('Spreadsheets::MAX_ROWS', 2)

      expect { import(Array.new(3) { |i| row("u#{i}@example.com") }) }.not_to change(Submission, :count)
      expect(response.body).to include('too many rows')
    end

    it 'does not create submissions for an archived template' do
      template.update!(archived_at: Time.current)

      expect { import([row('ann@example.com')]) }.not_to change(Submission, :count)
    end
  end
end
