module StaticPageDefaults
  module_function

  def definitions
    [
      {
        system_key: "privacy",
        slug: "datenschutz",
        title: "Datenschutz",
        kicker: "Service",
        intro: "Diese Seite fasst die wichtigsten Datenschutzangaben von StuttgartLIVE kompakt zusammen. Maßgeblich bleibt die ausführliche Datenschutzerklärung der bestehenden Website.",
        body: <<~HTML
          <div class="info-page-card">
            <h2>Verantwortliche Stelle</h2>
            <p>
              Südwestdeutsche Konzertdirektion Stuttgart Erwin Russ GmbH<br>
              Charlottenplatz 17<br>
              70173 Stuttgart
            </p>
            <p>
              Telefon: +49 (0) 711 1635311<br>
              E-Mail: <a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a>
            </p>
          </div>

          <div class="info-page-card">
            <h2>Hosting und technische Dienste</h2>
            <p>
              Beim Aufruf unserer Website werden technisch erforderliche Server-Logfiles verarbeitet,
              um den sicheren und stabilen Betrieb sicherzustellen. Dazu können insbesondere IP-Adresse,
              Zeitpunkt des Zugriffs, aufgerufene URL und Browser-Informationen gehören.
            </p>
          </div>

          <div class="info-page-card">
            <h2>Datenschutzbeauftragter</h2>
            <p>
              DataSecurITy UG (haftungsbeschränkt)<br>
              Kirchstraße 42<br>
              89180 Berghülen
            </p>
            <p>
              Telefon: +49 (0) 7344 92 48 49 0<br>
              E-Mail: <a href="mailto:datenschutz@datasecurity-ug.de">datenschutz@datasecurity-ug.de</a>
            </p>
          </div>

          <div class="info-page-card">
            <h2>Newsletter, Kontakt und Sitzungen</h2>
            <p>
              Bei Newsletter-Anmeldungen und Kontaktanfragen werden die von Ihnen übermittelten Daten
              ausschließlich zur Bearbeitung Ihrer Anfrage oder zur Zustellung des Newsletters genutzt.
              Im geschützten Redaktionsbereich werden zudem technisch notwendige Sitzungsdaten gespeichert,
              damit Anmeldungen und Sicherheitsfunktionen zuverlässig funktionieren.
            </p>
          </div>

          <div class="info-page-card">
            <h2>Google Analytics 4</h2>
            <p>
              Für die Reichweitenmessung kann Google Analytics 4 eingesetzt werden. Eine Aktivierung erfolgt
              ausschließlich nach Ihrer ausdrücklichen Einwilligung. Ohne Zustimmung bleibt Analytics deaktiviert.
            </p>
          </div>

          <div class="info-page-card">
            <h2>YouTube und externe Inhalte</h2>
            <p>
              Eingebettete Videos und andere Drittinhalte werden standardmäßig blockiert. Erst nach Ihrer
              Einwilligung werden diese Inhalte geladen und dabei Daten an den jeweiligen Anbieter übertragen.
            </p>
          </div>

          <div class="info-page-card">
            <h2>Ihre Rechte</h2>
            <p>
              Sie haben insbesondere das Recht auf Auskunft, Berichtigung, Löschung, Einschränkung der
              Verarbeitung sowie Widerspruch gegen bestimmte Verarbeitungen. Außerdem können erteilte
              Einwilligungen jederzeit mit Wirkung für die Zukunft widerrufen werden.
            </p>
            <p>
              Ihre Auswahl können Sie jederzeit über die Schaltfläche Datenschutzeinstellungen
              im Footer anpassen.
            </p>
          </div>

          <div class="info-page-card info-page-card-wide">
            <h2>Vollständige Datenschutzerklärung</h2>
            <p>
              Die ausführliche Fassung der Datenschutzerklärung finden Sie auf der bisherigen Website:
              <a href="https://stuttgart-live.de/datenschutz/" target="_blank" rel="noopener">stuttgart-live.de/datenschutz</a>
            </p>
          </div>
        HTML
      },
      {
        system_key: "imprint",
        slug: "impressum",
        title: "Impressum",
        kicker: "Service",
        intro: "Anbieter- und Kontaktinformationen zu Stuttgart Live und den verantwortlichen Gesellschaften.",
        body: <<~HTML
          <div class="info-page-card">
            <h2>SKS Erwin Russ GmbH</h2>
            <dl class="info-page-list">
              <div>
                <dt>Firmensitz</dt>
                <dd>Charlottenplatz 17, 70173 Stuttgart, Deutschland</dd>
              </div>
              <div>
                <dt>Register</dt>
                <dd>HRB 14984 · Amtsgericht Stuttgart</dd>
              </div>
              <div>
                <dt>USt-IdNr.</dt>
                <dd>DE 147867476</dd>
              </div>
              <div>
                <dt>Geschäftsführer</dt>
                <dd>Michaela Russ, Burkhard Glashoff</dd>
              </div>
              <div>
                <dt>Mitgliedschaft</dt>
                <dd>Verband Deutscher Konzertdirektionen e.V.</dd>
              </div>
            </dl>
          </div>

          <div class="info-page-card">
            <h2>Stuttgart Live</h2>
            <dl class="info-page-list">
              <div>
                <dt>Marke der</dt>
                <dd>SKS Michael Russ GmbH</dd>
              </div>
              <div>
                <dt>Geschäftsführer</dt>
                <dd>Michaela Russ, Paul Woog</dd>
              </div>
              <div>
                <dt>Register</dt>
                <dd>HRB Nr. 23472, Amtsgericht Stuttgart</dd>
              </div>
              <div>
                <dt>USt-IdNr.</dt>
                <dd>DE 225 570 318</dd>
              </div>
              <div>
                <dt>Firmensitz</dt>
                <dd>Charlottenplatz 17, 70173 Stuttgart, Deutschland</dd>
              </div>
            </dl>
          </div>

          <div class="info-page-card info-page-card-wide">
            <h2>Urheberrecht</h2>
            <p>
              Alle Inhalte sind urheberrechtlich geschützt. Die auf der Website verwendeten Texte, Bilder,
              Grafiken, Sounds und Dateien dürfen ohne Zustimmung nicht weitergegeben, verändert oder
              gewerblich genutzt werden.
            </p>
          </div>

          <div class="info-page-card info-page-card-wide">
            <h2>Hinweis zu externen Links</h2>
            <p>
              Für Inhalte verlinkter externer Websites sind die jeweiligen Anbieter verantwortlich.
              Stuttgart Live übernimmt keine Verantwortung für Darstellungen, Inhalte oder Verbindungen
              auf Seiten Dritter.
            </p>
            <p>
              Eine Haftung für fremde Inhalte besteht nur ab positiver Kenntnis und soweit die Verhinderung
              der Nutzung technisch möglich und zumutbar ist.
            </p>
          </div>

          <div class="info-page-card">
            <h2>Fragen zur Seite</h2>
            <dl class="info-page-list">
              <div>
                <dt>Telefon</dt>
                <dd><a href="tel:+497111635327">0711 – 16353-27</a></dd>
              </div>
              <div>
                <dt>E-Mail</dt>
                <dd><a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a></dd>
              </div>
            </dl>
          </div>
        HTML
      },
      {
        system_key: "terms",
        slug: "agb",
        title: "AGB",
        kicker: "Service",
        intro: "Für Ticketkäufe über Stuttgart Live gelten je nach Bestellweg die Bedingungen des jeweils eingebundenen Ticketanbieters sowie die nachstehenden Servicehinweise.",
        body: <<~HTML
          <div class="info-page-card">
            <h2>Ticketkauf über Partner</h2>
            <p>
              Der eigentliche Vertragsabschluss erfolgt in der Regel über den jeweiligen Ticketdienst,
              etwa Easy Ticket, Eventim oder Reservix. Maßgeblich sind deshalb die AGB, Zahlungs-,
              Versand- und Widerrufsbedingungen des ausgewählten Partners.
            </p>
          </div>

          <div class="info-page-card">
            <h2>Mailorder und telefonischer Service</h2>
            <p>
              Zusätzlich bietet Stuttgart Live persönliche Unterstützung bei der Ticketauswahl. Für
              telefonische Bestellungen und Mailorder-Anfragen können Sie sich an
              <a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a> oder die Bestell-Hotline
              wenden. Verfügbarkeit, Preisstufen und Versand richten sich nach dem konkreten Angebot.
            </p>
          </div>

          <div class="info-page-card">
            <h2>Preise und Verfügbarkeit</h2>
            <p>
              Alle Preise verstehen sich vorbehaltlich Verfügbarkeit. Gebühren, Versandkosten und
              Zusatzleistungen können je nach Ticketanbieter und Versandart abweichen.
            </p>
          </div>

          <div class="info-page-card">
            <h2>Reklamationen</h2>
            <p>
              Sollten Tickets nach einer Bestellung nicht eintreffen oder Rückfragen zu einer Buchung
              bestehen, wenden Sie sich bitte unter Angabe Ihrer Bestelldaten an das Stuttgart-Live-Team,
              damit der Vorgang geprüft werden kann.
            </p>
          </div>

          <div class="info-page-card info-page-card-wide">
            <h2>Ergänzende Hinweise</h2>
            <p>
              Für veranstaltungsbezogene Sonderregelungen, Hausordnungen, Altersfreigaben oder
              Sicherheitsauflagen gelten zusätzlich die Angaben auf der jeweiligen Eventseite und die
              Bedingungen des Veranstaltungsortes.
            </p>
          </div>
        HTML
      },
      {
        system_key: "accessibility",
        slug: "barrierefreiheit",
        title: "Barrierefreiheit",
        kicker: "Service",
        intro: "Diese Seite informiert über den aktuellen Stand der digitalen Barrierefreiheit von Stuttgart Live sowie über Kontakt- und Feedbackmöglichkeiten bei bestehenden Hürden.",
        body: <<~HTML
          <div class="info-page-card">
            <h2>Geltungsbereich</h2>
            <p>
              Diese Erklärung bezieht sich auf die Website von Stuttgart Live. Ziel ist es, die Inhalte
              für möglichst viele Menschen zugänglich zu machen und bestehende Barrieren schrittweise
              abzubauen.
            </p>
          </div>

          <div class="info-page-card">
            <h2>Stand der Vereinbarkeit</h2>
            <p>
              Die Website ist nach eigener Einschätzung derzeit nur teilweise mit den Anforderungen an
              digitale Barrierefreiheit vereinbar. Einzelne Bereiche befinden sich noch in technischer
              und redaktioneller Überarbeitung.
            </p>
          </div>

          <div class="info-page-card">
            <h2>Bekannte Einschränkungen</h2>
            <p>
              Je nach Inhaltsbereich kann es derzeit noch Barrieren geben, etwa bei eingebetteten
              Medien, älteren redaktionellen Inhalten, alternativen Bildbeschreibungen, Kontrasten oder
              der vollständigen Bedienbarkeit einzelner Komponenten per Tastatur.
            </p>
          </div>

          <div class="info-page-card">
            <h2>Feedback und Kontakt</h2>
            <p>
              Wenn Sie auf Barrieren stoßen oder Inhalte in einer besser zugänglichen Form benötigen,
              können Sie sich an Stuttgart Live wenden.
            </p>
            <p>
              Stuttgart Live / SKS Michael Russ GmbH<br>
              Charlottenplatz 17<br>
              70173 Stuttgart
            </p>
            <p>
              E-Mail: <a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a><br>
              Telefon: <a href="tel:+497111635311">+49 (0) 711 1635311</a>
            </p>
          </div>

          <div class="info-page-card">
            <h2>Schlichtung und Durchsetzung</h2>
            <p>
              Sollte Ihre Rückmeldung nicht zufriedenstellend beantwortet werden, können Sie sich an die
              zuständige Durchsetzungs- oder Schlichtungsstelle für digitale Barrierefreiheit wenden.
              Die offiziellen Informationen dazu finden Sie auf der bisherigen Website von Stuttgart Live.
            </p>
          </div>

          <div class="info-page-card info-page-card-wide">
            <h2>Bestehende Informationsseite</h2>
            <p>
              Die ursprüngliche Fassung dieser Hinweise finden Sie weiterhin unter:
              <a href="https://stuttgart-live.de/barrierefreiheit/" target="_blank" rel="noopener">stuttgart-live.de/barrierefreiheit</a>
            </p>
          </div>
        HTML
      },
      {
        system_key: "contact",
        slug: "kontakt",
        title: "Kontakt",
        kicker: "Service",
        intro: "Direkte Ansprechpartner für Bestellungen, Presse und Veranstaltungsnews.",
        body: <<~HTML
          <div class="info-page-card">
            <h2>Bestell-Hotline</h2>
            <dl class="info-page-list">
              <div>
                <dt>Telefon</dt>
                <dd><a href="tel:+4971155066077">0711 – 550 660 77</a></dd>
              </div>
              <div>
                <dt>Mailorder</dt>
                <dd><a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a></dd>
              </div>
            </dl>
          </div>

          <div class="info-page-card">
            <h2>Pressekontakt</h2>
            <dl class="info-page-list">
              <div>
                <dt>Ansprechpartner</dt>
                <dd>Arnulf Woock</dd>
              </div>
              <div>
                <dt>Adresse</dt>
                <dd>Charlottenplatz 17, 70173 Stuttgart</dd>
              </div>
              <div>
                <dt>Fon</dt>
                <dd><a href="tel:+497111635320">+49 (0) 711 16 353 20</a></dd>
              </div>
              <div>
                <dt>Mail</dt>
                <dd><a href="mailto:arnulfwoock@russ-live.de">arnulfwoock@russ-live.de</a></dd>
              </div>
            </dl>
          </div>

          <div class="info-page-card info-page-card-wide">
            <h2>Veranstaltungsnews</h2>
            <p>
              Bitte schicken Sie Ihre Veranstaltungs- und Pressenews an
              <a href="mailto:news@stuttgart-live.de">news@stuttgart-live.de</a>.
            </p>
          </div>

          <div class="info-page-card info-page-card-wide">
            <h2>Folgen Sie uns online</h2>
            <div class="info-page-links">
              <a href="https://www.facebook.com/stuttgartlive" target="_blank" rel="noopener">Facebook</a>
              <a href="https://www.instagram.com/stuttgartlive/" target="_blank" rel="noopener">Instagram</a>
              <a href="https://www.tiktok.com/@stuttgartlive" target="_blank" rel="noopener">TikTok</a>
            </div>
          </div>
        HTML
      }
    ]
  end

  def ensure!
    definitions.each do |attributes|
      page = StaticPage.find_by(system_key: attributes[:system_key]) || StaticPage.find_by(slug: attributes[:slug])
      page ||= StaticPage.new
      body_missing = page.body.to_plain_text.blank?

      page.system_key ||= attributes[:system_key]
      page.slug ||= attributes[:slug]
      page.title ||= attributes[:title]
      page.kicker ||= attributes[:kicker]
      page.intro ||= attributes[:intro]
      page.body = attributes[:body] if body_missing
      page.save! if page.new_record? || page.changed? || body_missing
    end
  end
end
