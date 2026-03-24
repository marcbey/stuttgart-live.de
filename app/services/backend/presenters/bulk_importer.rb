module Backend
  module Presenters
    class BulkImporter
      Result = Struct.new(:created, :updated, :failed, :errors, keyword_init: true) do
        def any_errors?
          errors.any?
        end

        def total_processed
          created + updated + failed
        end
      end

      def self.extract_name(filename)
        basename = File.basename(filename.to_s, File.extname(filename.to_s))
        basename.tr("_-", " ").squish
      end

      def self.lookup_key(name)
        name.to_s.strip.downcase
      end

      def initialize(files:)
        @files = Array(files).compact_blank
      end

      def call
        if files.blank?
          return Result.new(
            created: 0,
            updated: 0,
            failed: 0,
            errors: [ "Bitte mindestens eine Datei auswählen." ]
          )
        end

        created = 0
        updated = 0
        failed = 0
        errors = []
        duplicate_keys = duplicate_name_keys

        files.each do |file|
          extracted_name = self.class.extract_name(file.original_filename)
          lookup_key = self.class.lookup_key(extracted_name)

          if extracted_name.blank?
            failed += 1
            errors << "#{display_filename(file)}: Kein Präsentator-Name aus dem Dateinamen ableitbar."
            next
          end

          if duplicate_keys.include?(lookup_key)
            failed += 1
            errors << "#{display_filename(file)}: Mehrere Uploads ergeben denselben Präsentator-Namen „#{extracted_name}“."
            next
          end

          unless image_file?(file)
            failed += 1
            errors << "#{display_filename(file)}: Datei muss ein Bild sein."
            next
          end

          matching_presenters = presenters_for_name(extracted_name)

          if matching_presenters.many?
            failed += 1
            errors << "#{display_filename(file)}: Mehrdeutiger vorhandener Präsentator-Name „#{extracted_name}“."
            next
          end

          presenter = matching_presenters.first

          if presenter.present?
            if presenter.update(logo: file)
              updated += 1
            else
              failed += 1
              errors << "#{display_filename(file)}: #{presenter.errors.full_messages.to_sentence}"
            end
          else
            presenter = Presenter.new(name: extracted_name)
            presenter.logo.attach(file)

            if presenter.save
              created += 1
            else
              failed += 1
              errors << "#{display_filename(file)}: #{presenter.errors.full_messages.to_sentence}"
            end
          end
        end

        Result.new(created:, updated:, failed:, errors:)
      end

      private

      attr_reader :files

      def duplicate_name_keys
        counts = Hash.new(0)

        files.each do |file|
          key = self.class.lookup_key(self.class.extract_name(file.original_filename))
          next if key.blank?

          counts[key] += 1
        end

        counts.select { |_key, count| count > 1 }.keys
      end

      def presenters_for_name(name)
        Presenter.where("LOWER(TRIM(name)) = ?", self.class.lookup_key(name)).to_a
      end

      def image_file?(file)
        file.content_type.to_s.start_with?("image/")
      end

      def display_filename(file)
        file.original_filename.presence || "Unbenannte Datei"
      end
    end
  end
end
