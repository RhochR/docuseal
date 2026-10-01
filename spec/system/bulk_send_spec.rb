# frozen_string_literal: true

RSpec.describe 'Bulk send from a spreadsheet' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:template) { create(:template, account:, author: user, only_field_types: %w[text]) }
  let(:csv_path) { Rails.root.join('tmp/bulk_send_spec.csv') }

  before do
    File.write(csv_path, "Name,Email,First Name\nAnn Smith,ann@example.com,Ann\nBob Jones,bob@example.com,Bob\n")

    sign_in(user)
  end

  after { FileUtils.rm_f(csv_path) }

  it 'imports a CSV file, maps the columns and creates a submission for every row' do
    visit new_template_submission_path(template)

    find('label', text: 'Upload List').click

    find('#import_list_file', visible: :all).set(csv_path.to_s)

    expect(page).to have_content('Total entries: 2')
    expect(page).to have_content('Recipient field')

    click_button 'Add Recipients'

    expect(page).to have_content('New recipients have been added', wait: 10)

    submitters = template.submissions.order(:id).map { |s| s.submitters.first }
    field_uuid = template.fields.find { |f| f['name'] == 'First Name' }['uuid']

    expect(submitters.map(&:email)).to eq(%w[ann@example.com bob@example.com])
    expect(submitters.map(&:name)).to eq(['Ann Smith', 'Bob Jones'])
    expect(submitters.map { |s| s.values[field_uuid] }).to eq(%w[Ann Bob])
  end

  it 'shows an error for a file that is not a spreadsheet' do
    File.write(csv_path.sub('.csv', '.txt'), 'hello')

    visit new_template_submission_path(template)

    find('label', text: 'Upload List').click

    page.accept_alert(/Unsupported file/) do
      find('#import_list_file', visible: :all).set(csv_path.sub('.csv', '.txt').to_s)
    end

    expect(page).to have_content('Upload CSV or XLSX Spreadsheet')
    expect(page).to have_no_content('Total entries')
  ensure
    FileUtils.rm_f(csv_path.sub('.csv', '.txt'))
  end
end
