# frozen_string_literal: true

RSpec.describe SubmitterMailer do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:folder) { create(:template_folder, account:) }
  let(:template) { create(:template, account:, author:, folder:) }
  let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author) }
  let(:submitter) { create(:submitter, submission:, uuid: template.submitters.first['uuid'], account:) }

  let(:html_template) do
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head><style>.button { background: #1a73e8; color: #fff; padding: 10px 20px }</style></head>
        <body>
          <h1>Hello {{submitter.name}}</h1>
          <p><a class="button" href="{{submitter.link}}">Review and sign {{template.name}}</a></p>
          <script>alert(1)</script>
        </body>
      </html>
    HTML
  end

  def html_of(mail)
    (mail.html_part || mail).body.decoded
  end

  def text_of(mail)
    mail.deliver_now

    ActionMailer::Base.deliveries.last.text_part&.body&.decoded.to_s
  end

  shared_examples 'a custom HTML email' do
    it 'sends the template as a single document with the attribution' do
      html = html_of(mail)

      expect(html.scan('<html').size).to eq(1)
      expect(html).to include('class="button"')
      expect(html).to include("Review and sign #{template.name}")
      expect(html).not_to include('<script')
      expect(html.scan('data-attribution').size).to eq(1)
      expect(html).to include('open-source software')
    end

    it 'has a plain text alternative with the attribution' do
      text = text_of(mail)

      expect(text).to include(template.name)
      expect(text.gsub(/\s+/, ' ')).to include('open-source software')
      expect(text).not_to include('.button {')
    end
  end

  describe '#invitation_email' do
    let(:mail) { described_class.invitation_email(submitter) }

    it 'wraps a plain text message in the layout as before' do
      submitter.template.update!(preferences: { 'request_email_body' => 'Please sign {{submitter.link}}' })

      expect(html_of(mail).scan('<html').size).to eq(1)
      expect(html_of(mail)).to include('Please sign')
      expect(html_of(mail)).not_to include('data-attribution')
    end

    context 'with an HTML template in the account settings' do
      before do
        create(:account_config, account:, key: AccountConfig::SUBMITTER_INVITATION_EMAIL_KEY,
                                value: { 'subject' => 'Sign', 'body' => html_template })
      end

      it_behaves_like 'a custom HTML email'

      it 'fills in the variables' do
        submitter.update!(name: 'Bob <b>Builder</b>')

        html = html_of(mail)

        expect(html).to include('Hello Bob &lt;b&gt;Builder&lt;/b&gt;')
        expect(html).to match(%r{href="https?://[^"]+/s/#{submitter.slug}})
      end
    end

    context 'with an HTML template on the template' do
      before { template.update!(preferences: { 'request_email_body' => html_template }) }

      it_behaves_like 'a custom HTML email'
    end

    context 'with an HTML message from the API' do
      before do
        message = EmailMessage.create!(account:, author:, subject: 'Sign', body: html_template)

        submitter.update!(preferences: { 'email_message_uuid' => message.uuid })
      end

      it_behaves_like 'a custom HTML email'
    end

    context 'when the HTML template has no link' do
      before { template.update!(preferences: { 'request_email_body' => '<html><body><p>Hello</p></body></html>' }) }

      it 'adds the link to the signing form before the attribution' do
        document = Nokogiri::HTML5(html_of(mail))

        expect(document.at_css("body a[href*='/s/#{submitter.slug}']")).to be_present
        expect(document.at_css('body').element_children.last['data-attribution']).to eq('true')
      end

      it 'does not add the link for API submissions' do
        submission.update!(source: :api)

        expect(html_of(described_class.invitation_email(submitter.reload))).not_to include("/s/#{submitter.slug}")
      end
    end
  end

  describe '#documents_copy_email' do
    before do
      template.update!(preferences: { 'documents_copy_email_body' => html_template,
                                      'documents_copy_email_attach_documents' => false,
                                      'documents_copy_email_attach_audit' => false })
      submitter.update!(completed_at: Time.current)
    end

    let(:mail) { described_class.documents_copy_email(submitter) }

    it_behaves_like 'a custom HTML email'
  end
end
