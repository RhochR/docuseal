# frozen_string_literal: true

RSpec.describe Submitters::CreateStampAttachment do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:folder) { create(:template_folder, account:) }
  let(:template) { create(:template, account:, author:, folder:) }
  let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author) }
  let(:submitter) { submission.submitters.first }

  describe '.load_logo' do
    it 'uses the DocuSeal stamp logo without a company logo' do
      expect(described_class.load_logo(submitter).read).to eq(PdfIcons.stamp_logo_io.read)
    end

    it 'uses the company logo when the account has one' do
      account.logo.attach(io: Rails.root.join('spec/fixtures/sample-image.png').open, filename: 'logo.png')

      expect(described_class.load_logo(submitter.reload).read).to eq(account.logo.download)
    end
  end
end
