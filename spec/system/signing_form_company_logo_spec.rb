# frozen_string_literal: true

RSpec.describe 'Signing Form with a company logo' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }

  context 'when the account has a company logo' do
    let(:template) { create(:template, shared_link: true, account:, author:, only_field_types: %w[text]) }
    let(:submission) { create(:submission, :with_submitters, template:) }
    let(:submitter) { submission.submitters.first }

    before do
      account.update_column(:name, 'Acme Corp')
      account.logo.attach(io: Rails.root.join('spec/fixtures/sample-image.png').open, filename: 'logo.png')
    end

    it 'shows the logo and the account name on the start page and keeps the attribution' do
      visit start_form_path(slug: template.slug)

      expect(page).to have_css("img[alt='#{account.name}']")
      expect(page).to have_no_css('h1', text: 'DocuSeal')
      expect(page).to have_content('Powered by DocuSeal')
    end

    it 'shows the logo in the signing form header and keeps the attribution' do
      visit submit_form_path(slug: submitter.slug)

      expect(page).to have_css("img[alt='#{account.name}']")
      expect(page).to have_content('Powered by DocuSeal')
    end
  end
end
