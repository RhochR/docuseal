# frozen_string_literal: true

RSpec.describe SubmitterMailer do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:) }
  let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author) }
  let(:submitter) { create(:submitter, submission:, uuid: template.submitters.first['uuid'], account:) }

  describe '#invitation_email' do
    let(:mail) { described_class.invitation_email(submitter) }
    let(:html) { (mail.html_part || mail).body.decoded }

    it 'has no logo image without a company logo' do
      expect(html).not_to include('<img')
    end

    context 'when the account has a company logo' do
      before do
        account.logo.attach(io: Rails.root.join('spec/fixtures/sample-image.png').open, filename: 'logo.png')
      end

      it 'shows the logo with an absolute URL and keeps the attribution' do
        expect(html).to match(%r{<img src="https?://[^"]+/file/[^"]+/logo\.png" alt="#{Regexp.escape(account.name)}"})
        expect(html).to include('open-source software')
        expect(html.scan('<img').size).to eq(1)
      end
    end
  end
end
