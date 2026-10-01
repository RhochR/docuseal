# frozen_string_literal: true

class AccountLogosController < ApplicationController
  MAX_FILE_SIZE = 2.megabytes
  MAX_DIMENSION = 400
  MAX_PIXELS = 25_000_000
  CONTENT_TYPES = %w[image/png image/jpeg].freeze

  before_action do
    authorize!(:update, current_account)
  end

  def create
    file = params[:file]

    return redirect_with_error unless file.respond_to?(:read) && file.size <= MAX_FILE_SIZE

    current_account.logo.attach(build_blob(file.read))

    redirect_to settings_personalization_path, notice: I18n.t('logo_has_been_uploaded')
  rescue ImageUtils::UnsupportedFormat, Vips::Error
    redirect_with_error
  end

  def destroy
    current_account.logo.purge

    redirect_to settings_personalization_path, notice: I18n.t('logo_has_been_removed')
  end

  private

  def redirect_with_error
    redirect_to settings_personalization_path, alert: I18n.t('unable_to_upload_logo')
  end

  def build_blob(data)
    content_type = Marcel::MimeType.for(StringIO.new(data))

    raise ImageUtils::UnsupportedFormat, content_type.to_s unless CONTENT_TYPES.include?(content_type)

    header = Vips::Image.new_from_buffer(data, '')

    raise ImageUtils::UnsupportedFormat, 'too large' if header.width * header.height > MAX_PIXELS

    # Decodes the image already reduced in size and applies the EXIF rotation.
    image = Vips::Image.thumbnail_buffer(data, MAX_DIMENSION, height: MAX_DIMENSION, size: :down)

    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(image.write_to_buffer('.png', strip: true)),
      filename: 'logo.png',
      content_type: 'image/png',
      metadata: { analyzed: true, identified: true, width: image.width, height: image.height }
    )
  end
end
