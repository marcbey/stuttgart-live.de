namespace :blog do
  desc "Importiere News-Beiträge von stuttgart-live.de via WordPress API"
  task :import_wordpress_news, [ :author_email ] => :environment do |_, args|
    author_email = args[:author_email].to_s.strip.downcase.presence || ENV["AUTHOR_EMAIL"].to_s.strip.downcase.presence
    author =
      if author_email.present?
        User.find_by!(email_address: author_email)
      else
        Blog::WordpressImporter.default_author
      end

    result = Blog::WordpressImporter.call(author: author)

    puts "Import abgeschlossen."
    puts "Autor: #{author.email_address}"
    puts "Neu: #{result.created_count}"
    puts "Aktualisiert: #{result.updated_count}"

    if result.errors.any?
      puts "Fehler:"
      result.errors.each do |error|
        puts "- #{error[:id]} #{error[:title]}: #{error[:error]}"
      end
    end
  end
end
