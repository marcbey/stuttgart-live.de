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
        system_key: "tickets",
        slug: "tickets",
        title: "Tickets",
        kicker: nil,
        intro: "Informationen zu Ticketkauf, Partnershops und dem direkten Ticketservice von Stuttgart Live.",
        body: <<~HTML
          <div class="info-page-card">
            <h2>Tickets online kaufen</h2>
            <p>Tickets für viele Veranstaltungen sind direkt über unsere angebundenen Partnershops erhältlich. Die Links führen jeweils zum passenden Ticketanbieter.</p>
            <p>
              <a href="https://partnershop.easyticket.de/3b38659fef6bcc38e100c728435ba8e9/" target="_blank" rel="noopener">Easy Ticket</a><br>
              <a href="https://www.eventim.de/?affiliate=SRU" target="_blank" rel="noopener">Eventim</a><br>
              <a href="https://stuttgart-live.reservix.de/events" target="_blank" rel="noopener">Reservix</a>
            </p>
          </div>

          <div class="info-page-card">
            <h2>Ticketservice</h2>
            <p>Bei Fragen zu Bestellungen, Versand oder Abholung hilft unser Ticketservice gerne weiter.</p>
            <p>Telefon: <a href="tel:+4971155066077">0711 – 550 660 77</a></p>
            <p>E-Mail: <a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a></p>
          </div>

          <div class="info-page-card">
            <h2>Tickets an der Abendkasse</h2>
            <p>Ob es eine Abendkasse gibt, hängt von der jeweiligen Veranstaltung ab. Hinweise dazu stehen nach Möglichkeit direkt beim Event.</p>
          </div>

          <div class="info-page-card">
            <h2>Verlegte oder abgesagte Veranstaltungen</h2>
            <p>Bei Terminänderungen gelten die Informationen des jeweiligen Veranstalters oder Ticketanbieters. Bereits gekaufte Tickets behalten in der Regel ihre Gültigkeit, sofern nichts anderes angegeben ist.</p>
          </div>
        HTML
      },
      {
        system_key: "contact",
        slug: "kontakt",
        title: "Kontakt",
        kicker: nil,
        intro: "Direkte Ansprechpartner für Tickets, Presse und Veranstaltungsnews.",
        body: <<~HTML
          <div class="info-page-card info-page-card-wide contact-form-card">
            <h2>Nachricht schreiben</h2>
            <form class="contact-mail-form" action="mailto:info@stuttgart-live.de" method="post" enctype="text/plain">
              <label>
                <span>Name</span>
                <input type="text" name="Name" autocomplete="name">
              </label>
              <label>
                <span>E-Mail</span>
                <input type="email" name="E-Mail" autocomplete="email">
              </label>
              <label class="contact-mail-form-full">
                <span>Nachricht</span>
                <textarea name="Nachricht" rows="6"></textarea>
              </label>
              <button type="submit">E-Mail vorbereiten</button>
            </form>
          </div>

          <div class="info-page-card">
            <h2>Ticketservice</h2>
            <p>Telefon: <a href="tel:+4971155066077">0711 – 550 660 77</a></p>
            <p>Mailorder: <a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a></p>
          </div>

          <div class="info-page-card">
            <h2>Pressekontakt</h2>
            <p>Arnulf Woock</p>
            <p>Charlottenplatz 17, 70173 Stuttgart</p>
            <p>Fon <a href="tel:+497111635320">+49 (0) 711 16 353 20</a></p>
            <p>Mail <a href="mailto:arnulfwoock@russ-live.de">arnulfwoock@russ-live.de</a></p>
          </div>

          <div class="info-page-card">
            <h2>Veranstaltungsnews</h2>
            <p>Bitte schicken Sie Ihre Veranstaltungs- und Pressenews an <a href="mailto:news@stuttgart-live.de">news@stuttgart-live.de</a>.</p>
          </div>

          <div class="info-page-card">
            <h2>Social Media</h2>
            <p>
              <a href="https://www.facebook.com/stuttgartlive" target="_blank" rel="noopener">Facebook</a><br>
              <a href="https://www.instagram.com/stuttgart.live.concert/" target="_blank" rel="noopener">Instagram</a><br>
              <a href="https://www.tiktok.com/@stuttgart.live.concert" target="_blank" rel="noopener">TikTok</a>
            </p>
          </div>
        HTML
      },
      {
        system_key: "faq",
        slug: "faq",
        title: "FAQ",
        kicker: nil,
        intro: "Antworten auf die häufigsten Fragen rund um Tickets, Versand, Abholung und Ermäßigungen.",
        body: <<~HTML
          <div class="info-page-card">
            <h2>Wie kann ich sehen, wo mein Platz ist?</h2>
            <p>Bei vielen Veranstaltungen können Plätze direkt über eine Saalplanbuchung ausgewählt werden. Dort wählen Sie Kategorie, Platz und bei Bedarf weitere Plätze aus.</p>
          </div>

          <div class="info-page-card">
            <h2>Wann und wie erhalte ich meine Tickets?</h2>
            <p>Online- und Mailorder-Bestellungen werden in der Regel postalisch zugestellt. Wir empfehlen versicherten Versand, da verlorene Tickets nicht immer ersetzt werden können.</p>
          </div>

          <div class="info-page-card">
            <h2>Was passiert mit meinen Daten?</h2>
            <p>Die Daten werden beim jeweiligen Ticketsystem für den Bestellvorgang verarbeitet. Hinterlegte E-Mail-Adressen oder Telefonnummern helfen, wenn es Verlegungen, Absagen oder Rückfragen zur Bestellung gibt.</p>
          </div>

          <div class="info-page-card">
            <h2>Was passiert bei Verlegung oder Absage?</h2>
            <p>Bereits gekaufte Karten behalten bei Verlegungen in der Regel ihre Gültigkeit. Informationen kommen vom Veranstalter, vom Veranstaltungsort oder über den jeweiligen Ticketanbieter.</p>
          </div>

          <div class="info-page-card">
            <h2>Kann ich zu viel gekaufte Karten zurückgeben?</h2>
            <p>Eintrittskarten sind grundsätzlich von Umtausch und Rückgabe ausgeschlossen. Privater Weiterverkauf ist nur ohne Preisaufschlag zulässig.</p>
          </div>

          <div class="info-page-card">
            <h2>Wie finde ich den Veranstaltungsort?</h2>
            <p>Der Veranstaltungsort ist bei jeder Veranstaltung aufgeführt. Dort finden Sie Adresse, Karte und meist auch weitere Anfahrtsinformationen des jeweiligen Hauses.</p>
          </div>

          <div class="info-page-card">
            <h2>Darf ich Ton, Film oder Video aufnehmen?</h2>
            <p>Ton-, Film- und Videoaufzeichnungen sind bei Veranstaltungen in der Regel nicht gestattet.</p>
          </div>

          <div class="info-page-card">
            <h2>Dürfen Kinder oder Jugendliche alleine kommen?</h2>
            <p>Altersfreigaben und Begleitregelungen hängen von Veranstaltung, Uhrzeit und Lautstärke ab. Wenn nichts Konkretes angegeben ist, fragen Sie bitte beim Team oder Veranstalter nach.</p>
          </div>

          <div class="info-page-card">
            <h2>Ist die Fahrt mit öffentlichen Verkehrsmitteln inklusive?</h2>
            <p>Ob ein Ticket zur kostenfreien ÖPNV-Nutzung berechtigt, steht auf der jeweiligen Veranstaltungsseite oder im Ticketshop.</p>
          </div>

          <div class="info-page-card">
            <h2>Was darf ich mitnehmen?</h2>
            <p>Glas, Dosen, pyrotechnische Gegenstände, Waffen sowie große Taschen oder Rucksäcke sind häufig untersagt. Details können je nach Veranstaltung und Veranstaltungsort abweichen.</p>
          </div>

          <div class="info-page-card">
            <h2>Darf ich Getränke, Verpflegung oder Regenschirme mitnehmen?</h2>
            <p>Eigene Getränke und Verpflegung sind im Allgemeinen nicht erlaubt. Regenschirme sind bei Open-Air-Veranstaltungen aus Sicherheits- und Sichtgründen meist ausgeschlossen.</p>
          </div>

          <div class="info-page-card">
            <h2>Was tun bei Kartenverlust?</h2>
            <p>Bitte wenden Sie sich mit Ihren Bestelldaten an den Kartenservice unter <a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a>.</p>
          </div>

          <div class="info-page-card">
            <h2>Rollstuhlfahrer und Menschen mit Behinderung</h2>
            <p>Für Rollstuhlfahrerbereiche werden meist gesonderte Tickets benötigt. Informationen dazu finden Sie beim Veranstalter, Veranstaltungsort oder über den Ticketservice.</p>
          </div>

          <div class="info-page-card">
            <h2>Feedback zu einer Veranstaltung</h2>
            <p>Bei Problemen vor Ort wenden Sie sich bitte direkt an Kasse, Ordner oder Hallen- bzw. Clubverwaltung. Spätere Reklamationen lassen sich oft nur eingeschränkt klären.</p>
          </div>

          <div class="info-page-card">
            <h2>Übernachtungen in Stuttgart</h2>
            <p>Informationen zu Übernachtungen bietet die Touristik-Information Stuttgart. Für Wohnmobile empfiehlt sich der Stuttgarter Campingplatz.</p>
          </div>

          <div class="info-page-card">
            <h2>Gesundheit und Sicherheit</h2>
            <p>Bitte achten Sie auf Gehörschutz, besonders bei Kindern, und trinken Sie ausreichend. Für medizinische Notfälle sind Sanitäter oder Ärzte vor Ort über das Ordnungspersonal erreichbar.</p>
          </div>

          <div class="info-page-card">
            <h2>Ich habe weitere Fragen</h2>
            <p>Der Ticketservice hilft telefonisch unter <a href="tel:+4971155066077">0711 – 550 660 77</a> oder per E-Mail an <a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a>.</p>
          </div>
        HTML
      },
      {
        system_key: "about",
        slug: "ueber-uns",
        title: "Über uns",
        kicker: nil,
        intro: "Stuttgart Live bündelt Veranstaltungshighlights, Konzerte und Kulturtermine für Stuttgart und die Region.",
        body: <<~HTML
          <div class="info-page-card">
            <h2>Stuttgart Live</h2>
            <p>Stuttgart Live ist ein Angebot der Südwestdeutschen Konzertdirektion Erwin Russ GmbH und Teil der Konzertdirektion Russ, einer der ältesten Konzertdirektionen in Deutschland.</p>
          </div>

          <div class="info-page-card">
            <h2>Russ Klassik und Russ Live</h2>
            <p>Die SKS Erwin Russ steht für hochwertige Klassik. Die SKS Michael Russ realisiert Unterhaltung vom kleinen Club bis zum Open Air, von Shows bis zu internationalen Stars.</p>
          </div>

          <div class="info-page-card">
            <h2>Events und Dienstleistungen</h2>
            <p>Neben eigenen Veranstaltungen unterstützt Russ Unternehmen bei großen Shows und Events, Produkteinführungen, Industriemessen und Firmenjubiläen inklusive individueller Organisation und Sicherheitskonzepten.</p>
          </div>

          <div class="info-page-card">
            <h2>Premiumpartner</h2>
            <p>Zu den Ticketpartnern gehören Easy Ticket, Reservix und Eventim. Weitere Partner kommen unter anderem aus Mobilität, Hören, Optik und Gastronomie.</p>
          </div>

          <div class="info-page-card">
            <h2>Engagement</h2>
            <p>Stuttgart Live und die Konzertdirektion Russ unterstützen regionale Kultur-, Sozial- und Bildungsprojekte sowie Branchenverbände.</p>
          </div>

          <div class="info-page-card info-page-card-wide">
            <h2>Kontakt</h2>
            <p>Fragen zur Website, zu Tickets oder zu Veranstaltungen beantwortet das Stuttgart-Live-Team unter <a href="mailto:info@stuttgart-live.de">info@stuttgart-live.de</a>.</p>
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
