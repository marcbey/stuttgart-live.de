module Newsletter
  module ConsentText
    VERSION = "2026-10-22".freeze
    NEWSLETTER_TITLE = "Ich möchte den STUTTGART LIVE-Newsletter der Südwestdeutschen Konzertdirektion Erwin Russ GmbH per E-Mail erhalten.".freeze
    NEWSLETTER_DETAILS = "Der Newsletter informiert insbesondere über Konzerte, Veranstaltungen, Vorverkäufe und weitere Angebote von STUTTGART LIVE. Meine Einwilligung kann ich jederzeit mit Wirkung für die Zukunft über den Abmeldelink in jeder Newsletter-E-Mail oder durch Mitteilung an STUTTGART LIVE widerrufen. Weitere Informationen enthält die Datenschutzerklärung.".freeze
    TRACKING_TITLE = "Ich bin damit einverstanden, dass die Südwestdeutsche Konzertdirektion Erwin Russ GmbH mithilfe des Newsletter-Dienstes Mailjet mein Öffnungs- und Klickverhalten im STUTTGART LIVE-Newsletter personenbezogen auswertet.".freeze
    TRACKING_DETAILS = "Hierbei wird erfasst, ob und wann ich einen Newsletter öffne und welche darin enthaltenen Links ich anklicke. Die Auswertung dient der Messung und Optimierung von Newsletterinhalten und Angeboten. Die Einwilligung ist freiwillig und keine Voraussetzung für den Bezug des Newsletters. Ich kann diese Einwilligung jederzeit über die Tracking-Einstellungen im Newsletter oder durch Mitteilung an STUTTGART LIVE mit Wirkung für die Zukunft widerrufen, ohne den Newsletter abbestellen zu müssen. Weitere Informationen enthält die Datenschutzerklärung.".freeze
    FOOTER = "Wir verwenden Ihre E-Mail-Adresse für den Versand des STUTTGART LIVE-Newsletters. Die Anmeldung erfolgt im Double-Opt-In-Verfahren. Personenbezogene Öffnungs- und Klickmessungen erfolgen nur, wenn Sie hierzu gesondert einwilligen. Beide Einwilligungen können jederzeit mit Wirkung für die Zukunft widerrufen werden. Weitere Informationen finden Sie in unserer Datenschutzerklärung.".freeze
    CONFIRMATION_SUBJECT = "Bitte bestätigen Sie Ihre Anmeldung zum STUTTGART LIVE-Newsletter".freeze
    CONFIRMATION_BODY = "Vielen Dank für Ihr Interesse am STUTTGART LIVE-Newsletter. Bitte bestätigen Sie Ihre Anmeldung über den folgenden Bestätigungslink. Erst nach Ihrer Bestätigung wird Ihre E-Mail-Adresse in unseren Newsletterverteiler aufgenommen. Wenn Sie sich nicht angemeldet haben, können Sie diese Nachricht ignorieren.".freeze

    def self.snapshot
      { "newsletter" => "#{NEWSLETTER_TITLE} #{NEWSLETTER_DETAILS}", "tracking" => "#{TRACKING_TITLE} #{TRACKING_DETAILS}" }
    end
  end
end
