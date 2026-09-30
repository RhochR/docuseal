# frozen_string_literal: true

RSpec.describe Submissions::GenerateAuditTrail do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:folder) { create(:template_folder, account:) }
  let(:template) { create(:template, account:, author:, folder:) }
  let(:submission) { create(:submission, :with_submitters, :with_events, template:, created_by_user: author) }

  def image_count(document)
    document.pages.first.resources[:XObject].value.count { |_, xobject| xobject[:Subtype] == :Image }
  end

  before do
    submission.submitters.each { |s| s.update!(completed_at: Time.current, email: 'signer@example.com') }
  end

  it 'draws the DocuSeal mark only when the account has no logo' do
    document = described_class.build_audit_trail(submission.reload)

    expect(image_count(document)).to be >= 1
  end

  it 'adds the company logo next to the DocuSeal mark' do
    without_logo = image_count(described_class.build_audit_trail(submission.reload))

    account.logo.attach(io: Rails.root.join('spec/fixtures/sample-image.png').open, filename: 'logo.png',
                        content_type: 'image/png', metadata: { 'width' => 1600, 'height' => 1600 })

    with_logo = image_count(described_class.build_audit_trail(submission.reload))

    expect(with_logo).to eq(without_logo + 1)
  end
end
