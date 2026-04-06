require "base64"
require "openssl"
require "pathname"

module PublicMediaUrl
  module_function

  def enabled?
    config.enabled && secret.present?
  end

  def path_for(record)
    signed_media_path_for(record)
  end

  def url_for(record, url_options:)
    path = path_for(record)
    return if path.blank?

    options = url_options.to_h.symbolize_keys
    host = options[:host].presence
    return path if host.blank?

    protocol = options[:protocol].presence || "https"
    port = options[:port].presence

    URI::Generic.build(
      scheme: protocol.delete_suffix("://"),
      host: host,
      port: standard_port?(protocol, port) ? nil : port,
      path: path
    ).to_s
  end

  def signed_media_path_for(record)
    return unless enabled?

    media_file = media_file_for(record)
    return unless media_file

    expires_at = Time.current.to_i + config.ttl
    signature = signature_for(expires_at:, relative_path: media_file.relative_path)
    filename = ERB::Util.url_encode(media_file.filename.to_s)

    "/media/#{expires_at}/#{signature}/#{media_file.relative_path}--#{filename}"
  rescue StandardError => error
    Rails.logger.warn("PublicMediaUrl fallback for #{record.class}: #{error.class}: #{error.message}")
    nil
  end

  def media_file_for(record)
    storage_record = storage_record_for(record)
    return unless storage_record

    service = storage_record.service
    return unless service.is_a?(ActiveStorage::Service::DiskService)

    absolute_path = service.send(:path_for, storage_record.key)
    root = Pathname.new(File.expand_path(service.root.to_s))
    path = Pathname.new(File.expand_path(absolute_path))
    relative_path = path.relative_path_from(root).to_s

    MediaFile.new(
      filename: storage_record.filename.sanitized.to_s,
      relative_path:
    )
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::InvalidKeyError, ArgumentError
    nil
  end

  def storage_record_for(record)
    case record
    when ActiveStorage::Attached::One
      record.blob if record.attached?
    when ActiveStorage::Attachment
      record.blob if record.attached?
    when ActiveStorage::Blob
      record
    when ActiveStorage::VariantWithRecord
      record.processed.image.blob
    when ActiveStorage::Variant
      record.processed
    else
      if record.respond_to?(:blob) && record.respond_to?(:service) && record.respond_to?(:key) && record.respond_to?(:filename)
        record
      end
    end
  end

  def signature_for(expires_at:, relative_path:)
    digest = OpenSSL::Digest::MD5.digest("#{expires_at}/#{relative_path}#{secret}")

    Base64.strict_encode64(digest).tr("+/", "-_").delete("=")
  end

  def config
    Rails.configuration.x.media_proxy
  end

  def secret
    config.secret.to_s
  end

  def standard_port?(protocol, port)
    normalized_protocol = protocol.delete_suffix("://")
    normalized_port = port.to_i

    (normalized_protocol == "http" && normalized_port == 80) ||
      (normalized_protocol == "https" && normalized_port == 443)
  end

  MediaFile = Data.define(:filename, :relative_path)
end
