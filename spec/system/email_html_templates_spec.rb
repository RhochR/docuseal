# frozen_string_literal: true

RSpec.describe 'Email templates', :js do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }

  before do
    sign_in(user)
    visit settings_personalization_path
  end

  context 'with the signature request email' do
    let(:email_config_key) { AccountConfig::SUBMITTER_INVITATION_EMAIL_KEY }

    def open_signature_request_form
      form = find('.collapse', text: 'Signature Request Email')

      form.first('input[type="checkbox"]', visible: :all).click

      form
    end

    it 'saves the message as text by default' do
      form = open_signature_request_form

      within(form) do
        expect(page).to have_css('markdown-editor')
        expect(page).to have_no_css('email-editor', visible: :visible)

        click_button 'Save'
      end

      expect(page).to have_content('Settings have been saved.')
      expect(AccountConfig.find_by(account:, key: email_config_key).value['body']).not_to start_with('<!DOCTYPE')
    end

    it 'switches to an HTML template and keeps it after saving' do
      form = open_signature_request_form

      within(form) do
        find('label', text: 'HTML').click

        expect(page).to have_css('email-editor', visible: :visible, wait: 10)
        expect(page).to have_content('Available variables')
        expect(page).to have_content('A footer with a link to DocuSeal is added automatically')

        click_button 'Save'
      end

      expect(page).to have_content('Settings have been saved.')

      body = AccountConfig.find_by(account:, key: email_config_key).value['body']

      expect(body).to start_with('<!DOCTYPE html>')
      expect(body).to include('{{submitter.link}}')

      visit settings_personalization_path
      form = open_signature_request_form

      within(form) do
        expect(page).to have_css('email-editor', visible: :visible, wait: 10)
        expect(page).to have_no_css('markdown-editor', visible: :visible)
      end
    end

    it 'shows the preview with a policy that blocks everything but inline styles and secure images' do
      form = open_signature_request_form

      within(form) do
        find('label', text: 'HTML').click
        click_button 'Preview'

        iframe = find('iframe', visible: :all, wait: 10)

        expect(iframe[:srcdoc]).to include('Content-Security-Policy')
        expect(iframe[:srcdoc]).to include("default-src 'none'")
        expect(find('email-editor input[type="hidden"]', visible: :all,
                                                         match: :first).value).not_to include('Content-Security-Policy')
      end
    end
  end
end
