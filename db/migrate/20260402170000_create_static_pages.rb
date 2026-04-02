class CreateStaticPages < ActiveRecord::Migration[8.1]
  class MigrationStaticPage < ApplicationRecord
    self.table_name = "static_pages"
    has_rich_text :body
  end

  def up
    create_table :static_pages do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.string :kicker
      t.text :intro
      t.string :system_key

      t.timestamps
    end

    add_index :static_pages, :slug, unique: true
    add_index :static_pages, :system_key, unique: true

    MigrationStaticPage.reset_column_information

    static_pages_data.each do |attributes|
      body = attributes.delete(:body)
      MigrationStaticPage.create!(attributes.merge(body: body))
    end
  end

  def down
    ActionText::RichText.where(record_type: "StaticPage").delete_all
    drop_table :static_pages
  end

  private
    def static_pages_data
      [
        {
          system_key: "privacy",
          slug: "datenschutz",
          title: "Datenschutz",
          kicker: "Service",
          intro: "Hinweise zur Verarbeitung personenbezogener Daten auf Stuttgart Live und zu Ihren Rechten als betroffene Person.",
          body: <<~HTML
            <h2>Verantwortliche Stelle</h2>
            <p>SKS Michael Russ GmbH, Charlottenplatz 17, 70173 Stuttgart, Deutschland.</p>
            <p>E-Mail: <a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a></p>

            <h2>Datenschutzbeauftragter</h2>
            <p>Data Security UG</p>
            <p>E-Mail: <a href="mailto:datenschutz@datasecurity-ug.de">datenschutz@datasecurity-ug.de</a></p>

            <h2>Zugriffsdaten und Server-Logs</h2>
            <p>Beim Besuch dieser Website werden technisch notwendige Informationen wie IP-Adresse, Datum, Uhrzeit, aufgerufene URL, Referrer, Browsertyp und Betriebssystem verarbeitet, um die Seite sicher und stabil bereitzustellen.</p>

            <h2>Kontaktaufnahme</h2>
            <p>Wenn Sie uns per E-Mail kontaktieren, verarbeiten wir Ihre Angaben ausschließlich zur Bearbeitung Ihrer Anfrage und für mögliche Anschlussfragen.</p>

            <h2>Analyse und Einwilligungen</h2>
            <p>Optionale Dienste wie Google Analytics werden nur aktiviert, wenn Sie über das Consent-Banner zustimmen. Ihre Auswahl können Sie jederzeit über die Datenschutzeinstellungen im Footer ändern.</p>

            <h2>Ihre Rechte</h2>
            <p>Sie haben insbesondere das Recht auf Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung, Datenübertragbarkeit sowie Widerspruch gegen die Verarbeitung Ihrer personenbezogenen Daten.</p>

            <h2>Bestehende Informationsseite</h2>
            <p>Weitere Hinweise finden Sie auch unter <a href="https://stuttgart-live.de/datenschutz/" target="_blank" rel="noopener">stuttgart-live.de/datenschutz</a>.</p>
          HTML
        },
        {
          system_key: "imprint",
          slug: "impressum",
          title: "Impressum",
          kicker: "Service",
          intro: "Anbieter- und Kontaktinformationen zu Stuttgart Live und den verantwortlichen Gesellschaften.",
          body: <<~HTML
            <h2>SKS Erwin Russ GmbH</h2>
            <p>Firmensitz: Charlottenplatz 17, 70173 Stuttgart, Deutschland</p>
            <p>Register: HRB 14984 · Amtsgericht Stuttgart</p>
            <p>USt-IdNr.: DE 147867476</p>
            <p>Geschäftsführer: Michaela Russ, Burkhard Glashoff</p>
            <p>Mitgliedschaft: Verband Deutscher Konzertdirektionen e.V.</p>

            <h2>Stuttgart Live</h2>
            <p>Marke der SKS Michael Russ GmbH</p>
            <p>Geschäftsführer: Michaela Russ, Paul Woog</p>
            <p>Register: HRB Nr. 23472, Amtsgericht Stuttgart</p>
            <p>USt-IdNr.: DE 225 570 318</p>
            <p>Firmensitz: Charlottenplatz 17, 70173 Stuttgart, Deutschland</p>

            <h2>Urheberrecht</h2>
            <p>Alle Inhalte sind urheberrechtlich geschützt. Die auf der Website verwendeten Texte, Bilder, Grafiken, Sounds und Dateien dürfen ohne Zustimmung nicht weitergegeben, verändert oder gewerblich genutzt werden.</p>

            <h2>Hinweis zu externen Links</h2>
            <p>Für Inhalte verlinkter externer Websites sind die jeweiligen Anbieter verantwortlich. Stuttgart Live übernimmt keine Verantwortung für Darstellungen, Inhalte oder Verbindungen auf Seiten Dritter.</p>
            <p>Eine Haftung für fremde Inhalte besteht nur ab positiver Kenntnis und soweit die Verhinderung der Nutzung technisch möglich und zumutbar ist.</p>

            <h2>Fragen zur Seite</h2>
            <p>Telefon: <a href="tel:+497111635327">0711 – 16353-27</a></p>
            <p>E-Mail: <a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a></p>
          HTML
        },
        {
          system_key: "terms",
          slug: "agb",
          title: "AGB",
          kicker: "Service",
          intro: "Allgemeine Hinweise zu Ticketkauf, Verfügbarkeit und ergänzenden Services rund um Stuttgart Live.",
          body: <<~HTML
            <h2>Ticketkauf über Partner</h2>
            <p>Tickets werden je nach Veranstaltung über Partner wie Easy Ticket, Eventim oder Reservix angeboten. Für den eigentlichen Kauf gelten die Bedingungen des jeweiligen Ticketanbieters.</p>

            <h2>Mailorder und telefonischer Service</h2>
            <p>Unser Mailorder- und Telefonservice unterstützt bei Fragen zum Kaufprozess und zur Verfügbarkeit. Ein Vertrag kommt erst mit dem jeweiligen Ticketpartner zustande.</p>

            <h2>Preise und Verfügbarkeit</h2>
            <p>Alle Preise und Verfügbarkeiten können sich kurzfristig ändern. Maßgeblich sind die Angaben im Ticketshop des jeweiligen Partners zum Zeitpunkt der Bestellung.</p>

            <h2>Reklamationen</h2>
            <p>Bei Fragen zu Buchungen, Umbuchungen, Rückgaben oder Reklamationen wenden Sie sich bitte direkt an den Ticketanbieter, bei dem der Kauf erfolgt ist.</p>

            <h2>Ergänzende Hinweise</h2>
            <p>Stuttgart Live stellt Informationen zu Veranstaltungen zusammen und verlinkt auf die jeweils verfügbaren Kaufmöglichkeiten. Eigene AGB gelten nur dort, wo Stuttgart Live selbst ausdrücklich als Vertragspartner auftritt.</p>
          HTML
        },
        {
          system_key: "accessibility",
          slug: "barrierefreiheit",
          title: "Barrierefreiheit",
          kicker: "Service",
          intro: "Informationen zur digitalen Barrierefreiheit auf Stuttgart Live, bekannten Einschränkungen und Kontaktmöglichkeiten für Feedback.",
          body: <<~HTML
            <h2>Geltungsbereich</h2>
            <p>Diese Erklärung zur Barrierefreiheit gilt für die Website von Stuttgart Live.</p>

            <h2>Stand der Vereinbarkeit</h2>
            <p>Wir arbeiten daran, die Anforderungen an digitale Barrierefreiheit fortlaufend umzusetzen und bestehende Hürden zu reduzieren.</p>

            <h2>Bekannte Einschränkungen</h2>
            <p>Einzelne eingebundene Inhalte, Medien oder externe Ticketstrecken können derzeit noch nicht vollständig barrierefrei sein.</p>

            <h2>Feedback und Kontakt</h2>
            <p>Wenn Ihnen Barrieren auffallen oder Sie Inhalte in einer zugänglicheren Form benötigen, schreiben Sie uns bitte an <a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a>.</p>

            <h2>Schlichtung und Durchsetzung</h2>
            <p>Wenn Sie keine zufriedenstellende Rückmeldung erhalten, können Sie sich an die zuständigen Stellen zur Schlichtung und Durchsetzung wenden.</p>

            <h2>Bestehende Informationsseite</h2>
            <p>Die bisherige Informationsseite bleibt unter <a href="https://stuttgart-live.de/barrierefreiheit/" target="_blank" rel="noopener">stuttgart-live.de/barrierefreiheit</a> erreichbar.</p>
          HTML
        },
        {
          system_key: "contact",
          slug: "kontakt",
          title: "Kontakt",
          kicker: "Service",
          intro: "Direkte Ansprechpartner für Bestellungen, Presse und Veranstaltungsnews.",
          body: <<~HTML
            <h2>Bestell-Hotline</h2>
            <p>Telefon: <a href="tel:+4971155066077">0711 – 550 660 77</a></p>
            <p>Mailorder: <a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a></p>

            <h2>Pressekontakt</h2>
            <p>Ansprechpartner: Arnulf Woock</p>
            <p>Adresse: Charlottenplatz 17, 70173 Stuttgart</p>
            <p>Fon: <a href="tel:+497111635320">+49 (0) 711 16 353 20</a></p>
            <p>Mail: <a href="mailto:arnulfwoock@russ-live.de">arnulfwoock@russ-live.de</a></p>

            <h2>Veranstaltungsnews</h2>
            <p>Bitte schicken Sie Ihre Veranstaltungs- und Pressenews an <a href="mailto:news@stuttgart-live.de">news@stuttgart-live.de</a>.</p>

            <h2>Folgen Sie uns online</h2>
            <ul>
              <li><a href="https://www.facebook.com/stuttgartlive" target="_blank" rel="noopener">Facebook</a></li>
              <li><a href="https://www.instagram.com/stuttgartlive/" target="_blank" rel="noopener">Instagram</a></li>
              <li><a href="https://www.tiktok.com/@stuttgartlive" target="_blank" rel="noopener">TikTok</a></li>
            </ul>
          HTML
        }
      ]
    end
end
