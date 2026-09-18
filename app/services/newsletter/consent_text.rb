module Newsletter
  module ConsentText
    VERSION = "2026-09-18".freeze
    NEWSLETTER_TITLE = "Ich möchte den StuttgartLIVE-Newsletter der Südwestdeutschen Konzertdirektion Erwin Russ GmbH per E-Mail erhalten.".freeze
    NEWSLETTER_DETAILS = "Der Newsletter informiert insbesondere über Konzerte, Veranstaltungen, Vorverkäufe und weitere Angebote von StuttgartLIVE. Meine Einwilligung kann ich jederzeit mit Wirkung für die Zukunft über den Abmeldelink in jeder Newsletter-E-Mail oder durch Mitteilung an StuttgartLIVE widerrufen. Weitere Informationen enthält die Datenschutzerklärung.".freeze
    TRACKING_TITLE = "Ich bin damit einverstanden, dass mein Öffnungs- und Klickverhalten im StuttgartLIVE-Newsletter personenbezogen ausgewertet wird.".freeze
    TRACKING_DETAILS = "Hierzu darf Mailjet erfassen, ob und wann ich Newsletter öffne und welche enthaltenen Links ich anklicke. Die Auswertung dient der Messung und Optimierung von Newsletterinhalten und Angeboten. Diese Einwilligung ist freiwillig, nicht Voraussetzung für den Newsletterbezug und kann jederzeit unabhängig von der Newsletter-Anmeldung mit Wirkung für die Zukunft widerrufen werden. Weitere Informationen enthält die Datenschutzerklärung.".freeze
    FOOTER = "Wir verwenden Ihre E-Mail-Adresse für den Versand des StuttgartLIVE-Newsletters. Die Anmeldung erfolgt im Double-Opt-In-Verfahren. Personenbezogene Öffnungs- und Klickmessungen erfolgen nur, wenn Sie hierzu gesondert einwilligen. Beide Einwilligungen können jederzeit mit Wirkung für die Zukunft widerrufen werden. Weitere Informationen finden Sie in unserer Datenschutzerklärung.".freeze
    CONFIRMATION_SUBJECT = "Bitte bestätigen Sie Ihre Anmeldung zum StuttgartLIVE-Newsletter".freeze
    CONFIRMATION_BODY = "Vielen Dank für Ihr Interesse am StuttgartLIVE-Newsletter. Bitte bestätigen Sie Ihre Anmeldung über den folgenden Bestätigungslink. Erst nach Ihrer Bestätigung wird Ihre E-Mail-Adresse in unseren Newsletterverteiler aufgenommen. Wenn Sie sich nicht angemeldet haben, können Sie diese Nachricht ignorieren.".freeze

    def self.snapshot
      { "newsletter" => "#{NEWSLETTER_TITLE} #{NEWSLETTER_DETAILS}", "tracking" => "#{TRACKING_TITLE} #{TRACKING_DETAILS}" }
    end
  end
end
