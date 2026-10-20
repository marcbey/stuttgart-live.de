# Facebook und Instagram für Stuttgart Live einrichten

Diese Anleitung führt Marc und Chantal von den bisherigen Testverbindungen zu den echten Facebook- und Instagram-Konten. Marc hat Admin-Zugang zu unserer Anwendung auf stuttgart-live.de und übernimmt deren Konfiguration und Deployment. Chantal hat mit `chantalerler@russ-live.de` ebenfalls bereits Admin-Zugang zu unserer Anwendung. Sie verwaltet außerdem die bestehende technische Meta-App und kennt die echten Social-Media-Konten. Sie richtet die Meta-Seite der Verbindung ein und meldet sich anschließend mit den echten Social-Media-Zugängen an. Danach prüfen beide die Veröffentlichung.

**Die Reihenfolge ist wichtig: Erst korrigiert Chantal die Einstellungen bei Meta und Marc die Konfiguration unserer Anwendung. Sobald beide ihre Einrichtung bestätigt haben, ersetzt Chantal die Testverbindungen.**

## Wie die Systeme zusammenarbeiten

| System | Was es macht | Wer dort arbeitet |
| --- | --- | --- |
| Unsere Anwendung auf stuttgart-live.de | Hier entstehen Beiträge. Die Anwendung speichert die von Meta erteilten Freigaben und veröffentlicht damit später auf den ausgewählten Konten. | Marc richtet die Anwendung ein. Chantal verbindet die Konten und arbeitet redaktionell. |
| Technische Meta-App im Entwickler-Dashboard | Das ist die Registrierung unserer Integration bei Meta. Sie legt fest, welche Website sich verbinden darf und welche Funktionen unsere Anwendung anfordern kann. | Chantal. Marc hat hier keinen Verwaltungszugang. |
| Facebook | Chantal meldet sich mit ihrem persönlichen Facebook-Profil an. Dieses Profil muss die echte Facebook-Seite verwalten dürfen. Die Seite ist das Veröffentlichungsziel. | Chantal, bei fehlenden Rechten zusätzlich der Admin des Unternehmensportfolios oder der Seite. |
| Instagram | Chantal meldet sich direkt beim echten Instagram-Professional-Konto an. Dieses Konto ist das Veröffentlichungsziel für Instagram. | Chantal oder die Person, die den direkten Kontozugang hat. |

Die technische Meta-App ist keine Facebook-Seite und kein Instagram-Profil. Eine Freigabe der Website in der Meta-App entscheidet deshalb noch nicht, auf welcher Seite Beiträge erscheinen.

Beim Verbinden passiert Folgendes:

1. Chantal klickt **in unserer Anwendung** auf `Facebook verbinden` oder `Instagram verbinden`.
2. Unsere Anwendung schickt ihren Browser **zu Facebook beziehungsweise Instagram**. Die technische Meta-App benennt dabei unsere Integration und die benötigten Rechte.
3. Chantal meldet sich dort mit dem richtigen Konto an und erteilt die Freigabe.
4. Facebook beziehungsweise Instagram schickt den Browser **zurück zu unserer Anwendung**. Diese Rückkehradresse heißt Callback-URL.
5. Unsere Anwendung speichert einen Freigabeschlüssel, einen sogenannten Token, und die erlaubten Zielkonten. Damit kann sie später Beiträge veröffentlichen, ohne bei jedem Beitrag erneut nach einer Anmeldung zu fragen.

**Facebook und Instagram werden bei uns getrennt verbunden.** Für den direkten Instagram-Login ist grundsätzlich keine Verknüpfung mit einer Facebook-Seite erforderlich. Unsere Anwendung verwendet beim Instagram-Bildupload allerdings zusätzlich die verbundene Facebook-Seite als Zwischenstation für das Bild. Deshalb in dieser Anleitung zuerst Facebook und danach Instagram einrichten. Die Facebook-Anmeldung ersetzt den Instagram-Login nicht. [Meta beschreibt den direkten Instagram-Login und die dafür verwendeten Berechtigungen in seiner offiziellen API-Dokumentation](https://www.postman.com/meta/instagram/folder/6raa77c/instagram-api-with-instagram-login).

## Wer welche Zugänge braucht

| Person oder Rolle | Benötigter Zugang | Aufgabe |
| --- | --- | --- |
| Marc | Vorhandener Admin-Zugang zu unserer Anwendung sowie Projekt und Deployment von stuttgart-live.de | Die Konfiguration unserer Anwendung korrigieren, prüfen und deployen. |
| Chantal in der technischen Meta-App | Vorhandener Verwaltungszugang zu `stuttgart-live (admin app)` im Meta-Entwickler-Dashboard | Domains, Callback-URLs, App-Berechtigungen und gegebenenfalls Einladungen verwalten. Die App-IDs mit Marc abgleichen. |
| Chantal beim Verbindungsaufbau | Vorhandener Admin-Zugang zu unserer Anwendung mit `chantalerler@russ-live.de`, persönliches Facebook-Profil mit Zugriff auf die echte Seite, direkter Zugang zum echten Instagram-Konto | Die richtigen Kontonamen eintragen, die echten Konten freigeben und in unserer Anwendung verbinden. |
| Admin des Unternehmensportfolios oder der Facebook-Seite | Verwaltung des Unternehmens und seiner Social-Media-Konten | Falls nötig Chantals fehlende Seitenrechte ergänzen. Diese Person ist nicht automatisch der Meta-App-Admin. |

Die drei Berechtigungen **Admin unserer Anwendung**, **Verwaltung der Meta-App** und **Zugriff auf die Facebook-Seite** gelten unabhängig voneinander. Marc ist Admin unserer Anwendung und kann die Meta-App trotzdem nicht verwalten. Chantal kann die Meta-App verwalten und hat den für den Verbindungsaufbau benötigten Admin-Zugang zu unserer Anwendung bereits. Eine zusätzliche Benutzeranlage oder Rollenänderung ist nicht erforderlich. Marc muss für diesen Ablauf keinen Verwaltungszugang zur Meta-App erhalten.

## Ausgangslage am 19. Oktober 2026

Bei der Produktionsprüfung war Facebook mit `Test SL` und Instagram mit `@sl_test_26` verbunden. Der vorhandene Facebook-Token durfte ausschließlich auf `Test SL` zugreifen. Das Instagram-Testtoken war ungültig oder abgelaufen.

Die laufende Anwendung und die Meta-App verwiesen beim Callback beziehungsweise bei Domain und Website noch auf `stuttgart-live.schopp3r.de`. Die Callback-Korrektur auf `stuttgart-live.de` war zu diesem Zeitpunkt lokal vorbereitet, aber noch nicht deployt. Die Testverbindungen waren noch nicht entfernt.

Eine Änderung der Callback-URL ersetzt die gespeicherten Testkonten nicht. Dafür sind die späteren Anmeldungen von Chantal erforderlich.

## Stand am 20. Oktober 2026

Chantal hat die Anpassung von Domain, Website und Callback-Einstellungen im Meta-App-Dashboard als umgesetzt gemeldet. Die lesende Prüfung der Meta-App bestätigt, dass `stuttgart-live.de` jetzt zu den App-Domains gehört und die Website-URL `https://stuttgart-live.de/` lautet. Die erlaubten OAuth-Redirect-URIs wurden darüber nicht unabhängig ausgelesen.

Chantal hat außerdem die echten Zielkonten und beide App-IDs bestätigt. Die IDs stimmen mit der lokalen Konfiguration und der laufenden Produktion überein; dafür ist keine Änderung erforderlich.

Bei der Prüfung vor dem Deployment verwendete die laufende Produktion weiterhin die alte Callback-URL auf `stuttgart-live.schopp3r.de`. Facebook war dort noch mit `Test SL` verbunden, Instagram mit `@sl_test_26`. Für die technische Umstellung deployt Marc die Callback-Korrektur über den regulären GitHub-Freigabeablauf und kontrolliert die wirksame URL. Erst danach verbindet Chantal die beiden unten genannten echten Konten.

## Schritt 1 Marc und Chantal verwenden die bestätigten Zielkonten

**Wo:** Die öffentlichen Facebook- und Instagram-Profile; die Angaben stammen aus Chantals Rückmeldung vom 20. Oktober 2026.

| Angabe | Bestätigter Wert |
| --- | --- |
| Echte Facebook-Seite | [Stuttgart Live](https://www.facebook.com/Stuttgart.LIVE/) |
| Echtes Instagram-Konto | [@stuttgart.live.concert](https://www.instagram.com/stuttgart.live.concert/) |
| Meta-App-ID | `961318776384123` |
| Instagram-App-ID | `1389206203013880` |
| Persönliches Facebook-Profil für den Login | Chantal verwendet ihr Profil, das die echte Seite verwalten darf |
| Person mit Verwaltung der bestehenden Meta-App | Chantal |
| Admin und technischer Ansprechpartner unserer Anwendung | Marc |
| Person, die fehlenden Seitenzugriff vergeben kann | Chantal benennt bei Bedarf den Seiten- oder Unternehmensadmin |

Passwörter und Tokens gehören nicht in diese Abstimmung. Chantal führt die Anmeldungen später selbst aus.

**Ergebnis:** Die Zielkonten und App-IDs stehen fest. `Test SL` und `@sl_test_26` sind ausdrücklich nicht die Zielkonten. Diese Angaben ersetzen den späteren Login und die Freigabe durch Chantal nicht.

## Schritt 2 Chantal prüft ihren Zugriff auf die echten Konten

**Wo:** In Facebook und in der Instagram-App oder auf der Instagram-Website.

### Facebook prüfen

1. Chantal meldet sich bei [Facebook](https://www.facebook.com/) mit ihrem persönlichen Profil an, das die echte Seite verwaltet.
2. Über das Profilbild und `Alle Profile ansehen` wechselt sie zur echten Facebook-Seite.
3. Auf der Seite öffnet sie `Einstellungen und Privatsphäre` → `Einstellungen` → `Seiteneinrichtung` → `Seitenzugriff`. Dort prüft sie ihren Zugriff. Diesen Einstieg beschreibt auch die [Facebook-Hilfe zum Seitenzugriff](https://www.facebook.com/help/510247025775149/).
4. Falls die Rechte über ein Unternehmensportfolio verwaltet werden, prüft der zuständige Unternehmensadmin unter [Meta Business Suite](https://business.facebook.com/) → `Einstellungen` die Zuordnung von Chantal zur richtigen Seite und ihre Berechtigung zum Erstellen und Veröffentlichen von Inhalten.
5. Fehlt dieser Zugriff, ergänzt ihn der zuständige Seiten- oder Unternehmensadmin, bevor die Verbindung in unserer Anwendung gestartet wird.

Eine Facebook-Seite hat für diesen Ablauf keinen eigenen Login. Chantal verwendet ihr persönliches Profil und gibt darüber die Seite frei.

### Instagram prüfen

1. Chantal öffnet das echte Instagram-Profil und prüft den Benutzernamen aus Schritt 1.
2. In den Kontoeinstellungen prüft sie, ob es ein Professional-Konto vom Typ `Business` oder `Creator` ist. Je nach Oberfläche stehen diese Angaben unter `Für Profis`, `Kontoart und Tools` oder den Business-/Creator-Einstellungen. Der direkte API-Zugang unterstützt diese Kontotypen. [Quelle: Meta zur Instagram API mit Instagram Login](https://www.postman.com/meta/instagram/folder/1z5vxzu/instagram-api-with-instagram-login).
3. Sie prüft, dass sie sich direkt bei diesem Instagram-Konto anmelden kann und eine gegebenenfalls erforderliche Zwei-Faktor-Anmeldung abschließen kann. Zugriff über die Business Suite allein belegt diesen direkten Login noch nicht.
4. Fehlt der direkte Zugang oder ist das Konto noch ein Privatkonto, klärt Chantal das mit der kontoverantwortlichen Person, bevor sie fortfährt.

**Ergebnis:** Chantal kann die echte Facebook-Seite verwalten und sich direkt beim echten Instagram-Professional-Konto anmelden.

## Schritt 3 Chantal öffnet die bestehende technische Meta-App

**Wo:** Im [Meta-Entwickler-Dashboard der bestehenden App](https://developers.facebook.com/apps/961318776384123/).

1. Chantal meldet sich mit ihrem Konto an, mit dem sie diese Meta-App verwalten kann.
2. Sie öffnet die bestehende App `stuttgart-live (admin app)` mit der App-ID `961318776384123`.
3. Sie führt die folgenden Schritte 4 und 5 selbst aus. Marc bearbeitet anschließend die Konfiguration unserer Anwendung in Schritt 6.

**Ergebnis:** Die zuständige Person kann die richtige bestehende Integration bearbeiten. Für den Wechsel der Social-Media-Konten wird keine neue Meta-App angelegt.

## Schritt 4 Chantal korrigiert Domain und Rückkehradressen bei Meta

**Wo:** In der in Schritt 3 geöffneten Meta-App.

Meta zeigt Menüs abhängig vom App-Typ und der Sprache unterschiedlich an. Die folgenden Bereichsnamen und Feldwerte bestimmen, was gesucht und geändert werden muss.

1. Unter `App-Einstellungen` → `Allgemeines` beziehungsweise `Grundlegende Einstellungen` trägt Chantal bei den App-Domains `stuttgart-live.de` ein. In dieses Feld gehört nur der Hostname, ohne `https://`.
2. Bei der Plattform `Website` trägt sie als Website-URL `https://stuttgart-live.de/` ein und speichert die Änderung.
3. Im vorhandenen Bereich `Facebook Login` beziehungsweise `Facebook Login for Business` → `Einstellungen` ergänzt sie bei den gültigen OAuth-Redirect-URIs die vollständige Adresse aus der folgenden Tabelle und speichert.
4. Im Bereich `Instagram` → API-Einrichtung **mit Instagram Login** öffnet sie die Einstellungen für den Instagram-Business-Login. Dort hinterlegt sie dieselbe vollständige Adresse als erlaubte OAuth-Redirect-URI und speichert. Dieser Schritt betrifft den direkten Instagram-Login, den unsere Anwendung verwendet.
5. Chantal liest die App-IDs in den jeweiligen Bereichen ab und gleicht diese öffentlichen Kennungen mit Marc und den folgenden Werten ab. Marc prüft später die zugehörigen App-Zugangsdaten in unserer Anwendung. Falls eine Kennung abweicht, klären beide zuerst, welches Setup tatsächlich verwendet werden soll.

| Einstellung | Wert für unsere Produktion |
| --- | --- |
| App-Domain | `stuttgart-live.de` |
| Website-URL | `https://stuttgart-live.de/` |
| Erlaubter Facebook-Callback | `https://stuttgart-live.de/backend/meta_connection/callback` |
| Erlaubter Instagram-Callback | `https://stuttgart-live.de/backend/meta_connection/callback` |
| In der Anwendung hinterlegte Meta-App-ID | `961318776384123` |
| In der Anwendung hinterlegte Instagram-App-ID | `1389206203013880` |

Die Instagram-App-ID kann innerhalb derselben technischen Meta-App separat ausgewiesen sein. Zwei unterschiedliche IDs bedeuten deshalb nicht automatisch, dass zwei eigenständige Meta-Apps angelegt werden müssen. Chantal ordnet die Instagram-ID im Dashboard dem tatsächlich verwendeten Instagram-Login-Setup zu und bestätigt diese Zuordnung gegenüber Marc.

**Ergebnis:** Beide Login-Verfahren dürfen zu `stuttgart-live.de` zurückkehren. Chantal hat die Meta- und Instagram-App-ID mit Marc abgeglichen; Marc verwendet diese Zuordnung in Schritt 6. Es wird dabei noch kein echtes Social-Media-Konto verbunden.

## Schritt 5 Chantal prüft die App-Berechtigungen und nimmt nötige Einladungen an

**Wo:** Chantal zuerst im Meta-App-Dashboard, anschließend bei Bedarf in ihrem Facebook- beziehungsweise Instagram-Konto.

Chantal prüft bei den Berechtigungen beziehungsweise den Anwendungsfällen der bestehenden Meta-App diese von unserer Anwendung benötigten Funktionen:

| Plattform | Benötigte technische Berechtigungen |
| --- | --- |
| Facebook | `pages_show_list`, `pages_read_engagement`, `pages_manage_posts` |
| Instagram | `instagram_business_basic`, `instagram_business_content_publish` |

Anschließend prüft Chantal, für welche Personen und Konten diese Berechtigungen aktuell verfügbar sind:

1. Wenn die App nur für berechtigte App-Mitglieder beziehungsweise Tester nutzbar ist, prüft Chantal, ob das persönliche Facebook-Profil aus Schritt 1 bereits eine passende App-Rolle hat. Ist genau dieses Profil bereits als App-Admin berechtigt, ist keine zusätzliche Einladung als Tester nötig. Verwendet sie für die echte Seite ein anderes Profil, richtet sie für dieses Profil die benötigte App-Rolle ein und nimmt eine gegebenenfalls erforderliche Einladung mit genau diesem Profil an.
2. Wenn das Instagram-Setup einen Instagram-Tester verlangt, fügt Chantal dort den **echten Instagram-Benutzernamen** aus Schritt 1 hinzu. Anschließend öffnet sie mit diesem Instagram-Konto die Einstellungen für `Apps und Websites`, sucht nach `Tester-Einladungen` und nimmt die ausstehende Einladung für diese Meta-App an. Falls Meta die Einladungen in einer anderen Kontoverwaltung anzeigt, folgt sie dem dort angezeigten Einladungsweg.
3. Wenn die Integration auch von Personen ohne solche App-Rollen genutzt werden soll, prüft Chantal im Dashboard die dafür erforderlichen Freigaben und führt die gegebenenfalls verlangte App Review, Advanced-Access-Freigabe oder Unternehmensverifizierung durch. Sie bestätigt gegenüber Marc, sobald die Voraussetzungen für den vorgesehenen Login erfüllt sind.

Eine App-Tester-Rolle ist eine technische Zugangsberechtigung. Sie macht aus Chantals echter Facebook-Seite oder ihrem echten Instagram-Konto kein Testkonto. Umgekehrt erteilt eine App-Rolle allein noch keinen Zugriff auf eine Facebook-Seite; dafür gilt weiterhin Schritt 2.

Der Livebetrieb unserer Website und der Freigabestatus der Meta-App sind getrennte Einstellungen. Die Veröffentlichung von stuttgart-live.de schaltet Meta-Berechtigungen nicht automatisch frei.

**Ergebnis:** Chantals vorgesehener Login und das echte Instagram-Konto erfüllen die von Meta angezeigten Voraussetzungen. Etwaige Einladungen sind angenommen und nicht nur versendet.

## Schritt 6 Marc richtet unsere Anwendung fertig ein und deployt

**Wo:** Im Projekt stuttgart-live.de und anschließend im Backend von [stuttgart-live.de](https://stuttgart-live.de/).

1. Marc prüft in den Rails-Credentials die Zuordnung von `meta.app_id` und `meta.app_secret` sowie von `meta.instagram_app_id` und `meta.instagram_app_secret` zu den in Schritt 4 geprüften Einstellungen.
2. Er setzt `meta.instagram_redirect_uri` auf `https://stuttgart-live.de/backend/meta_connection/callback`. Trotz des historischen Namens gilt dieser Wert für Facebook **und** Instagram. Ein gesetzter Credentials-Wert hat Vorrang vor `META_INSTAGRAM_REDIRECT_URI` in der Umgebung.
3. Marc übernimmt die Änderung in den aktuellen Projektstand und führt die erforderlichen Prüfungen mit `mise exec -- bin/ci` aus. Vor einem Push aktualisiert er den Zielbranch gemäß den Projektregeln und führt die CI danach erneut erfolgreich aus. Anschließend deployt er über den bestehenden Produktionsablauf. Details zum Deployment stehen im [README](../README.md).
4. Nach dem Deployment prüft Marc in der laufenden Produktion die tatsächlich wirksame Callback-URL. Eine nur lokal geänderte Datei reicht nicht aus.

Chantals Benutzerkonto `chantalerler@russ-live.de` hat die benötigte Rolle `Admin` bereits. Für diesen Ablauf muss Marc keinen weiteren Zugang anlegen oder eine Rolle ändern.

**Ergebnis:** Die Produktion verwendet den richtigen Callback, und Chantal kann mit ihrem eigenen Zugang `Einstellungen` → `Meta Publishing` verwalten.

## Schritt 7 Marc und Chantal bestätigen die technische Einrichtung

**Wo:** Marc prüft unsere Produktion, Chantal prüft das Meta-App-Dashboard. Anschließend stimmen beide den Beginn des Verbindungsaufbaus ab.

Marc bestätigt Chantal:

- Die neue Konfiguration ist auf der laufenden Produktion angekommen.

Chantal bestätigt Marc:

- Sie kann mit `chantalerler@russ-live.de` die Meta-Einstellungen in unserer Anwendung öffnen.
- Die neue Rückkehradresse ist im Facebook- und Instagram-Login-Setup gespeichert.
- Die nötigen App-Freigaben beziehungsweise Einladungen sind geklärt und die echten Zielkonten aus Schritt 1 stehen fest.

**Erst danach führt Chantal die nächsten Schritte aus.** So werden die bisherigen Testverbindungen nicht entfernt, während der neue Verbindungsaufbau noch durch die alte Konfiguration blockiert ist.

## Schritt 8 Chantal ersetzt die Facebook-Testverbindung

**Wo:** Start und Ende in [unserer Anwendung unter Meta Publishing](https://stuttgart-live.de/backend/settings/edit?section=meta_connection); dazwischen im Facebook-Dialog.

1. Chantal verwendet ihren eigenen Browser beziehungsweise ihr eigenes Browserprofil. Sie prüft, dass Facebook dort mit dem persönlichen Profil aus Schritt 1 angemeldet ist. Bei unserer Anwendung meldet sie sich mit ihrem bestehenden Admin-Konto `chantalerler@russ-live.de` an. Das ist der Login unserer Anwendung; das Facebook-Profil prüft sie davon getrennt.
2. Sie öffnet `Einstellungen` → `Meta Publishing` auf **stuttgart-live.de**.
3. In der Karte **Facebook** prüft sie, dass dort noch `Test SL` steht. Sie klickt in genau dieser Karte auf `Verbindung trennen` und bestätigt das Trennen. Das entfernt die gespeicherte Verbindung aus unserer Anwendung; die Facebook-Seite und ihre Beiträge bleiben bei Facebook bestehen.
4. Sie klickt auf `Facebook verbinden`. Der Browser wechselt zu Facebook. Sie lässt diesen Ablauf im selben Browser weiterlaufen.
5. Im Facebook-Dialog prüft sie das verwendete persönliche Profil und den Namen unserer Integration. Falls Meta eine bisherige Anmeldung fortsetzen möchte, öffnet sie die dort angebotene Bearbeitung der Freigaben, statt eine alte Auswahl mit ausschließlich `Test SL` unverändert zu bestätigen.
6. Sie gibt die **echte Facebook-Seite aus Schritt 1** und die angeforderten Rechte für Seitenliste, Lesen der Seite und Veröffentlichen frei und schließt den Dialog ab.
7. Facebook leitet sie zurück zu unserer Anwendung. Wenn mehrere Seiten angeboten werden, wählt sie unter `Facebook-Seitenauswahl` → `Aktive Facebook-Seite` die echte Seite und klickt auf `Seite speichern`. Bei genau einer gefundenen Seite kann die Auswahl bereits automatisch erfolgt sein.
8. Sie kontrolliert, dass als aktive Facebook-Seite der echte Name und nicht `Test SL` angezeigt wird und der Verbindungsstatus keinen Fehler meldet.

**Wenn die echte Seite im Facebook-Dialog bei Punkt 6 fehlt:** Chantal beendet den unpassenden Dialog und prüft mit dem Seiten- oder Unternehmensadmin den Zugriff aus Schritt 2. In ihrem Facebook-Profil kann sie unter `Einstellungen` → `Business-Integrationen` die Freigaben der bestehenden Integration prüfen und die echte Seite ergänzen, soweit Meta diese Bearbeitung anbietet. Sie prüft außerdem die Voraussetzungen im Meta-App-Dashboard aus Schritt 5. Danach startet sie `Facebook verbinden` erneut. Das Speichern einer Seitenauswahl in unserer Anwendung kann eine fehlende Freigabe bei Meta nicht ersetzen.

**Ergebnis:** Unsere Anwendung besitzt einen neuen, für die echte Seite freigegebenen Token und hat diese Seite als aktives Facebook-Ziel ausgewählt.

## Schritt 9 Chantal ersetzt die Instagram-Testverbindung

**Wo:** Start und Ende in [unserer Anwendung unter Meta Publishing](https://stuttgart-live.de/backend/settings/edit?section=meta_connection); dazwischen im Instagram-Dialog.

1. Im selben Browser prüft Chantal, welches Konto auf [Instagram](https://www.instagram.com/) angemeldet ist. Falls nötig wechselt sie dort zum echten Instagram-Konto aus Schritt 1.
2. In unserer Anwendung öffnet sie wieder `Einstellungen` → `Meta Publishing`.
3. In der Karte **Instagram** prüft sie, dass noch `@sl_test_26` angezeigt wird. Sie klickt in genau dieser Karte auf `Verbindung trennen` und bestätigt. Die echte Facebook-Verbindung aus Schritt 8 bleibt dabei bestehen.
4. Sie klickt auf `Instagram verbinden`. Der Browser wechselt zu Instagram. Unsere Anwendung verwendet an dieser Stelle den direkten Instagram-Login.
5. Chantal meldet sich mit dem **echten Instagram-Konto aus Schritt 1** an, schließt gegebenenfalls die Zwei-Faktor-Anmeldung ab und erteilt die angeforderten Freigaben für Profilzugriff und Veröffentlichung. Sie kontrolliert den Benutzernamen, bevor sie bestätigt.
6. Nach der Rückkehr zu unserer Anwendung prüft sie in der Instagram-Karte den Benutzernamen. Dort muss jetzt das echte Konto stehen und nicht `@sl_test_26`.

Unter der Facebook-Seite kann zusätzlich ein Feld `Verknüpftes Instagram` erscheinen. Dieses Feld beschreibt eine Verknüpfung bei Facebook. Entscheidend für unseren direkten Instagram-Login ist die separate **Instagram-Karte**.

**Ergebnis:** Unsere Anwendung besitzt eine eigene gültige Instagram-Verbindung zum echten Professional-Konto.

## Schritt 10 Chantal und Marc prüfen eine echte Veröffentlichung

**Wo:** In unserer Anwendung beim Event im Tab `Social`, danach auf der echten Facebook-Seite und im echten Instagram-Profil.

1. Chantal kontrolliert in `Meta Publishing` noch einmal beide aktiven Kontonamen. Marc prüft bei einer Fehlermeldung die technische Ursache, bevor veröffentlicht wird.
2. Chantal wählt einen redaktionell freigegebenen Event-Beitrag mit Bild, der auf den echten Konten erscheinen darf.
3. Im Event-Editor öffnet sie `Social`, kontrolliert den Facebook-Entwurf und den dort genannten Facebook-Zielnamen und klickt für diesen Entwurf auf `veröffentlichen`.
4. Sie öffnet die echte Facebook-Seite und prüft, ob der Beitrag dort angekommen ist. Marc prüft bei Bedarf den Publish-Status in unserer Anwendung.
5. Anschließend kontrolliert sie den Instagram-Entwurf, den angezeigten Instagram-Benutzernamen und veröffentlicht diesen Entwurf separat.
6. Sie öffnet das echte Instagram-Profil und prüft den veröffentlichten Beitrag. Scheitert nur der Instagram-Bildupload, prüft Marc auch die echte Facebook-Verbindung, die unsere Anwendung für die Bildbereitstellung verwendet.

`veröffentlichen` erstellt einen echten öffentlichen Beitrag. Für diese Prüfung deshalb einen zur Veröffentlichung bestimmten Beitrag verwenden.

**Die Umstellung ist abgeschlossen, wenn beide echten Konten angezeigt werden und die beiden Veröffentlichungen auf den richtigen Konten sichtbar sind.**

## Wer bei welchem Fehler übernimmt

| Beobachtung | Zuständig | Nächster konkreter Schritt |
| --- | --- | --- |
| „Onboarding muss auf stuttgart-live.schopp3r.de gestartet werden“ | Marc | Schritt 6 prüfen: Ist die neue Credentials-Konfiguration wirklich in der laufenden Produktion angekommen? |
| Meta meldet eine unzulässige Rückkehradresse | Chantal bei Meta, Marc in unserer Anwendung | Chantal prüft den gespeicherten Callback aus Schritt 4; Marc prüft die von unserer Anwendung verwendete URL. Beide Werte müssen übereinstimmen. |
| Chantal sieht in unserer Anwendung „Nur Admins dürfen diesen Bereich verwalten“ | Chantal, bei Wiederholung Marc | Zuerst prüfen, ob sie in unserer Anwendung mit `chantalerler@russ-live.de` angemeldet ist. Dieses Konto hat bereits Admin-Rechte; tritt der Fehler damit auf, untersucht Marc den Zugriff. |
| Facebook bietet ausschließlich `Test SL` an | Chantal, bei fehlenden Seitenrechten der Seiten-/Unternehmensadmin | Richtiges persönliches Profil, Seitenzuweisung, Freigaben der Business-Integration und Meta-App-Berechtigungen prüfen; anschließend Facebook neu verbinden. |
| Die echte Seite wird bei Meta ausgewählt, erscheint nach erfolgreicher Rückkehr aber nicht in unserer Anwendung | Marc | Callback und den mit dem neuen Token gelieferten Seitenkatalog untersuchen. Chantal nennt Zeitpunkt und betroffene Seite. |
| Instagram meldet fehlende Entwickler- oder Testerberechtigung | Chantal | Im Meta-App-Dashboard die Einladung für genau das echte Konto prüfen und mit diesem Instagram-Konto annehmen. Falls keine Testrolle vorgesehen ist, den notwendigen App-Freigabestatus prüfen. |
| Instagram meldet eine ungültige App oder Client-ID | Chantal und Marc | Chantal prüft das Instagram-Login-Setup im Dashboard; Marc prüft die dazugehörige App-ID und das passende Secret in unserer Anwendung. |
| Die Rückkehr meldet, dass der Login nicht verifiziert werden konnte | Chantal, bei Wiederholung Marc | Einen neuen Verbindungsaufbau auf stuttgart-live.de im selben Browser beginnen; keine alten Login-Tabs weiterverwenden. |
| Nach dem Verbinden steht weiterhin das Instagram-Testkonto in der Instagram-Karte | Chantal | Angemeldetes Instagram-Konto prüfen und Schritt 9 mit dem richtigen Konto wiederholen. |
| Das Instagram-Konto wird korrekt angezeigt, aber das Veröffentlichen scheitert | Marc | Konkreten Publish-Fehler und die Facebook-Verbindung für die Bildbereitstellung prüfen; den Account nicht nur wegen eines Uploadfehlers erneut wechseln. |

## Technische Details für Marc

Die Abläufe, gespeicherten Verbindungen und der Token-Lifecycle stehen in [META_ONBOARDING.md](META_ONBOARDING.md). Chantal muss keine Tokens manuell erzeugen oder in Credentials eintragen. Unsere Anwendung erzeugt und speichert die benötigten Freigaben beim jeweiligen Verbindungsaufbau.

Ist eine Verbindung später abgelaufen oder widerrufen, übernimmt Chantal die erneute Anmeldung mit dem betroffenen echten Konto. Chantal übernimmt außerdem Änderungen an der technischen Meta-App und deren Berechtigungen. Marc übernimmt Konfigurationsfehler unserer Anwendung und die Prüfung von API- oder Veröffentlichungsfehlern; er stimmt dabei erforderliche Änderungen im Meta-App-Dashboard mit Chantal ab.
