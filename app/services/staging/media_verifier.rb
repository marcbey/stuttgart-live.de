require "digest"
require "base64"
require "pathname"

module Staging
  class MediaVerifier
    Error = Class.new(StandardError)

    def self.call(connection:, root: "/rails/storage")
      raise Error, "Medienprüfung benötigt Staging" unless connection.select_value("SELECT current_database()") == DataSanitizer::DATABASE
      base = Pathname.new(root).realpath
      connection.select_all("SELECT key, byte_size, checksum FROM active_storage_blobs").each do |blob|
        key = blob.fetch("key")
        raise Error, "Ungültiger Medienschlüssel" unless key.match?(/\A[a-zA-Z0-9_-]{4,255}\z/)
        file = base.join(key[0, 2], key[2, 2], key).realpath
        raise Error, "Medium fehlt oder liegt außerhalb von Staging" unless file.to_s.start_with?("#{base}/") && file.file? && file.size == blob.fetch("byte_size").to_i
        if blob["checksum"].present?
          checksum = Base64.strict_encode64(Digest::MD5.file(file).digest)
          raise Error, "Medienprüfsumme stimmt nicht" unless checksum == blob.fetch("checksum")
        end
      end
      true
    rescue Errno::ENOENT, Errno::EACCES
      raise Error, "Referenzierte Mediendatei fehlt oder ist nicht lesbar"
    end
  end
end
