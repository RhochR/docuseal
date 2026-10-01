# frozen_string_literal: true

describe 'Account logo' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }

  before { sign_in(user) }

  def sample_logo
    upload(Rails.root.join('spec/fixtures/sample-image.png').to_s, 'image/png')
  end

  def upload(path_or_io, content_type)
    Rack::Test::UploadedFile.new(path_or_io, content_type, true, original_filename: 'logo')
  end

  describe 'POST /settings/logo' do
    it 'stores the logo as a PNG that fits into 400 pixels' do
      big_png = Vips::Image.black(1200, 600, bands: 3).write_to_buffer('.png')

      post settings_logo_path, params: { file: upload(StringIO.new(big_png), 'image/png') }

      expect(response).to redirect_to(settings_personalization_path)

      logo = account.reload.logo

      expect(logo).to be_attached
      expect(logo.blob.content_type).to eq('image/png')
      expect([logo.blob.metadata['width'], logo.blob.metadata['height']]).to eq([400, 200])
      expect(Vips::Image.pngload_buffer(logo.download).width).to eq(400)
    end

    it 'replaces an existing logo' do
      2.times do
        post settings_logo_path, params: { file: sample_logo }
      end

      expect(ActiveStorage::Attachment.where(record: account, name: 'logo').count).to eq(1)
    end

    it 'rejects files that are not PNG or JPEG images' do
      svg = StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"/>')

      post settings_logo_path, params: { file: upload(svg, 'image/svg+xml') }

      expect(response).to redirect_to(settings_personalization_path)
      expect(flash[:alert]).to eq(I18n.t('unable_to_upload_logo'))
      expect(account.reload.logo).not_to be_attached
    end

    it 'rejects files larger than the limit' do
      png = Vips::Image.black(10, 10, bands: 3).write_to_buffer('.png')
      data = png + ('0' * AccountLogosController::MAX_FILE_SIZE)

      post settings_logo_path, params: { file: upload(StringIO.new(data), 'image/png') }

      expect(flash[:alert]).to eq(I18n.t('unable_to_upload_logo'))
      expect(account.reload.logo).not_to be_attached
    end

    it 'requires a file' do
      post settings_logo_path

      expect(flash[:alert]).to eq(I18n.t('unable_to_upload_logo'))
    end
  end

  describe 'serving the logo' do
    it 'is available without signing in, so it can be shown to signers and in emails' do
      post settings_logo_path, params: { file: sample_logo }

      path = ActiveStorage::Blob.proxy_path(account.reload.logo.blob)

      sign_out(user)
      get path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('image/png')
    end
  end

  describe 'DELETE /settings/logo' do
    it 'removes the logo' do
      post settings_logo_path, params: { file: sample_logo }

      delete settings_logo_path

      expect(response).to redirect_to(settings_personalization_path)
      expect(account.reload.logo).not_to be_attached
    end
  end

  describe 'Accounts.load_logo' do
    it 'returns nil without a logo' do
      expect(Accounts.load_logo(account)).to be_nil
    end

    it 'returns the logo attachment' do
      post settings_logo_path, params: { file: sample_logo }

      expect(Accounts.load_logo(account.reload)).to be_present
    end

    it 'falls back to the logo of the main account for testing accounts' do
      main = create(:account, :with_testing_account)
      testing = main.testing_accounts.first

      main.logo.attach(io: Rails.root.join('spec/fixtures/sample-image.png').open, filename: 'logo.png')

      expect(Accounts.load_logo(testing).blob).to eq(main.logo.blob)
    end
  end

  describe 'QR code poster' do
    let(:template) do
      create(:template, shared_link: true, account:, author: user, folder: create(:template_folder, account:))
    end

    it 'shows the company logo instead of the DocuSeal mark' do
      post settings_logo_path, params: { file: sample_logo }

      get template_share_link_qr_path(template)

      expect(response.body).to include(ActiveStorage::Blob.proxy_path(account.reload.logo.blob))
      expect(response.body).to include('DocuSeal')
    end
  end
end
