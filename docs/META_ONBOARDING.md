# Meta-Onboarding und Token-Lifecycle

Die [Einrichtungsanleitung für Marc und Chantal](SOCIAL_MEDIA_EINRICHTUNG.md) erklärt das Zusammenspiel der Systeme und führt mit klaren Zuständigkeiten vom Testbetrieb zu den echten Facebook- und Instagram-Konten. Dieses Dokument beschreibt die technische Umsetzung und den Token-Lifecycle.

## Zielbild

`stuttgart-live` verwendet eine technische Meta-App, aber zwei getrennte persistierte Verbindungen:

- Instagram-Login für das Instagram-Professional-Konto
- Facebook-Business-Login für verwaltete Facebook-Seiten
- getrennte Health Checks, Tokens, Publish-Buttons und Publish-Versuche

Ein Event-Social-Post kann dadurch unabhängig auf Instagram oder Facebook veröffentlicht werden. Instagram und Facebook haben getrennte Drafts mit eigenen `event_social_posts`-Records; nicht veröffentlichte Drafts werden beim Hinzufügen oder Ändern des Eventbilds automatisch neu erzeugt, damit das aktuelle Eventbild verwendet wird.

## Persistierte Daten

### `social_connections`

Speichert je Plattform eine Meta-Verbindung:

- `provider = meta`
- `platform = instagram` oder `facebook`
- `auth_mode = instagram_login` oder `facebook_login_for_business`
- verschlüsseltes `user_access_token`
- `user_token_expires_at`
- `granted_scopes`
- `connection_status`
- `connected_at`
- `last_token_check_at`
- `last_refresh_at`
- `reauth_required_at`
- `last_error`

`provider` ist nicht mehr global eindeutig; eindeutig ist `provider + platform`.

### `social_connection_targets`

Speichert die im Onboarding gefundenen Ziele:

- `instagram_account` mit `external_id`, `username` und Metadaten an der Instagram-Verbindung
- `facebook_page` mit `external_id`, `name`, verschlüsseltem Page-Access-Token und Seiten-Metadaten an der Facebook-Verbindung

Die aktive Facebook-Seite ist ein `selected`-`facebook_page`-Target der Facebook-Verbindung. Der operative Instagram-Account ist ein `selected`-`instagram_account`-Target der Instagram-Verbindung.

### `publish_attempts`

Jeder Plattformversuch wird separat protokolliert mit:

- betroffenem `event_social_post`
- verwendeter `social_connection`
- verwendetem `social_connection_target`
- Start- und Endzeit
- Status `started`, `succeeded` oder `failed`
- Fehlermeldung
- Request-/Response-Snapshot ohne rohe Secrets

## Onboarding-Flows

Der Backend-Einstieg liegt im Settings-Tab `Meta Publishing`.

### Instagram

1. Admin klickt auf `Instagram verbinden`.
2. Die App startet den Instagram-Login-OAuth-Flow über `https://www.instagram.com/oauth/authorize`.
3. Der Callback tauscht den Code serverseitig gegen ein Short-lived User-Token.
4. Die App verlängert es zu einem Long-lived Token.
5. Die App lädt das Instagram-Professional-Profil.
6. Die Verbindung wird als `platform = instagram` persistiert.
7. Der Instagram-Account wird als selected `instagram_account`-Target gespeichert.

### Facebook

1. Admin klickt auf `Facebook verbinden`.
2. Die App startet den Facebook-Business-OAuth-Flow über `https://www.facebook.com/v25.0/dialog/oauth`.
3. Der Callback tauscht den Code serverseitig gegen ein Short-lived User-Token.
4. Die App verlängert es zu einem Long-lived User-Token.
5. Danach lädt die App über `me/accounts` alle verwalteten Facebook-Seiten inklusive Page-Access-Token.
6. Die Verbindung wird als `platform = facebook` persistiert.
7. Die gefundenen Seiten werden als `facebook_page`-Targets gespeichert.
8. Wenn genau eine Seite existiert, wird sie automatisch ausgewählt; sonst bleibt die Verbindung auf `pending_selection`.

Facebook-Publishing setzt keine Instagram-Verknüpfung der Seite mehr voraus.

## Verbindung trennen

Im Settings-Tab `Meta Publishing` kann jede Plattform getrennt werden. `Instagram Verbindung trennen` löscht nur die Instagram-Verbindung inklusive Instagram-Target. `Facebook Verbindung trennen` löscht nur die Facebook-Verbindung inklusive gespeicherter Facebook-Seiten und Page-Access-Tokens. Die jeweils andere Plattform bleibt unverändert verbunden.

## Erwartete Konfiguration

In Rails-Credentials oder ENV werden nur App-Zugangsdaten und optional die feste Callback-URL konfiguriert:

- `meta.app_id` oder `META_APP_ID`
- `meta.app_secret` oder `META_APP_SECRET`
- optional `meta.instagram_app_id` oder `META_INSTAGRAM_APP_ID`
- optional `meta.instagram_app_secret` oder `META_INSTAGRAM_APP_SECRET`
- optional `meta.instagram_redirect_uri` oder `META_INSTAGRAM_REDIRECT_URI`

Facebook verwendet `meta.app_id` und `meta.app_secret`. Instagram verwendet bevorzugt `meta.instagram_app_id` und `meta.instagram_app_secret`, weil der Instagram-Login-Dialog eine Instagram-Platform-App erwartet. Wenn diese Werte fehlen, fällt die App auf `meta.app_id` und `meta.app_secret` zurück.

Nicht in Credentials gehören:

- Facebook-Page-IDs als aktive Zielauswahl
- Facebook-Page-Access-Tokens
- Instagram-Business-Account-IDs

Wenn `meta.instagram_redirect_uri` gesetzt ist, verwendet die App diese Callback-URL explizit statt die URL aus dem aktuellen Request zu bauen. Der Name ist historisch Instagram-spezifisch, die URL gilt aber für beide Meta-Flows, also Instagram und Facebook. Der OAuth-Start und der Callback müssen dabei auf demselben Host laufen, weil der `state` serverseitig an die Session gebunden ist.

Für Produktion ist `https://stuttgart-live.de/backend/meta_connection/callback` hinterlegt. Credentials haben Vorrang vor ENV: Solange der Credentials-Schlüssel gesetzt ist, ändert `META_INSTAGRAM_REDIRECT_URI` die wirksame URL nicht. Nach einer Änderung der verschlüsselten Credentials ist ein erneutes Deployment erforderlich.

## Meta-App-Konfiguration

Die technische Meta-App muss zu `stuttgart-live` passen:

- App-Domain `stuttgart-live.de`
- Website-URL `https://stuttgart-live.de/`
- erlaubte OAuth-Redirect-URL `https://stuttgart-live.de/backend/meta_connection/callback` im Facebook- und im Instagram-Login-Setup
- Instagram API with Instagram Login mit `instagram_business_basic` und `instagram_business_content_publish`
- Facebook Login/Login for Business mit `pages_show_list`, `pages_read_engagement` und `pages_manage_posts`

Welche App Review, Advanced-Access-Freigaben oder App-Rollen erforderlich sind, hängt vom vorgesehenen Nutzerkreis und dem Freigabestatus der Meta-App ab. Der Livebetrieb unserer Website schaltet diese Rechte nicht automatisch frei. Im eingeschränkten App-Betrieb müssen die verwendeten Personen und Konten die von Meta verlangten Rollen beziehungsweise Tester-Einladungen besitzen und angenommen haben. Eine solche Rolle ist von der Auswahl einer Testseite oder eines echten Veröffentlichungskontos unabhängig. Die Prüfung und Zuständigkeiten stehen in der [Einrichtungsanleitung](SOCIAL_MEDIA_EINRICHTUNG.md#schritt-5-chantal-prüft-die-app-berechtigungen-und-nimmt-nötige-einladungen-an).

## Fehlerbehebung

### Onboarding verweist nach einem Domainwechsel auf den alten Host

Die Meldung „Onboarding muss auf … gestartet werden“ entsteht in der Anwendung vor der Weiterleitung zu Meta. Sie bedeutet, dass die fest konfigurierte Callback-URL nicht zum aktuellen Aufruf passt.

1. Im Meta-App-Dashboard App-Domain und Website-URL auf die Produktionsdomain anpassen. Die vollständige Callback-URL `https://stuttgart-live.de/backend/meta_connection/callback` sowohl für Facebook Login als auch für Instagram Login freigeben. Falls Instagram eine eigene App-ID verwendet, deren Konfiguration ebenfalls prüfen.
2. In den Rails-Credentials `meta.instagram_redirect_uri` auf diese URL setzen und die Anwendung neu deployen. Eine ENV-Änderung allein überschreibt einen vorhandenen Credentials-Wert nicht.
3. Das Backend über `https://stuttgart-live.de` öffnen und den Verbindungsaufbau dort neu starten. Ein bereits begonnener OAuth-Flow muss neu gestartet werden, damit Session und Callback zusammenpassen.

Die Hostprüfung muss bestehen bleiben: Eine Weiterleitung des Callbacks auf die alte Domain würde die Bindung an die Session des Start-Hosts verletzen.

### Facebook zeigt nur die Testseite oder die gewünschte Seite fehlt

Die Seitenauswahl wird aus den von Meta über `me/accounts` gelieferten und gespeicherten Zielen aufgebaut. Ein vorhandener Scope wie `pages_show_list` bedeutet nicht automatisch, dass jede verwaltete Seite freigegeben ist; die Berechtigung kann auf einzelne Seiten beschränkt sein.

1. Mit dem Facebook-Login anmelden, der die gewünschte echte Seite verwalten und dort Inhalte veröffentlichen darf. Den Seitenzugriff beziehungsweise die Zuweisung im Business Portfolio prüfen.
2. In den Einstellungen der bestehenden Meta-Business-Integration prüfen, welche Seiten für die App freigegeben sind, und die echte Seite hinzufügen. App-Rollen und den Freigabestatus der benötigten Berechtigungen im Meta-App-Dashboard ebenfalls prüfen, wenn der echte Account im Meta-Dialog fehlt.
3. Im Backend `Facebook verbinden` erneut durchlaufen, damit der Callback den Seitenkatalog mit der neuen Freigabe lädt. Das Speichern der bestehenden Seitenauswahl erteilt keine zusätzlichen Rechte bei Meta.
4. Die echte Seite im Backend auswählen und speichern. Mit einem abgelaufenen oder ungültigen Instagram-Token muss zusätzlich `Instagram verbinden` mit dem gewünschten Professional-Konto erneut durchlaufen werden.

Für eine technische Diagnose lassen sich `me/accounts` und `debug_token` mit dem gespeicherten Token ausschließlich lesend prüfen. Dabei auf weitere Ergebnisseiten und auf `granular_scopes.target_ids` achten. Liefert Meta nur die Testseite und beschränkt die Seiten-Scopes auf deren ID, liegt die fehlende Freigabe vor der Seitenauswahl unserer App. Tokens und App-Secrets dürfen dabei weder protokolliert noch in Screenshots oder Support-Nachrichten übernommen werden.

### Von Testkonten auf die echten Social-Media-Konten wechseln

Die verbundenen Facebook-Seiten und Instagram-Konten sind zusammen mit den beim Login erteilten Tokens in der Datenbank gespeichert. Eine Änderung der Callback-URL oder der App-Zugangsdaten ersetzt diese Verbindungen nicht. Auch das manuelle Ändern einer Account-ID erteilt dem vorhandenen Token keine Rechte für ein anderes Konto.

1. Zuerst die Produktionsdomain und Callback-URL abgleichen: Marc übernimmt unsere Anwendung, Chantal das Meta-App-Dashboard. Chantal prüft außerdem, ob die benötigten Berechtigungen und App-Rollen die Verbindung der echten Konten erlauben.
2. Anschließend führt die Person mit Zugriff auf die echten Social-Media-Konten den Wechsel unter `Einstellungen -> Meta Publishing` aus. Für Facebook die bisherige Testverbindung über `Verbindung trennen` entfernen, `Facebook verbinden` starten und mit dem Login anmelden, der die echte Seite verwalten darf. Die echte Seite bei Meta freigeben und anschließend im Backend auswählen und speichern.
3. Für Instagram ebenfalls die Testverbindung trennen und `Instagram verbinden` mit dem echten Professional-Konto durchlaufen. Instagram verwendet einen eigenen Login; die Auswahl der Facebook-Seite stellt diese Verbindung nicht automatisch um.
4. Vor der ersten Veröffentlichung prüfen, dass im Backend der Name der echten Facebook-Seite und der richtige Instagram-Benutzername angezeigt werden und beide Verbindungen verwendbar sind.

Fehlt die echte Seite bereits im Meta-Freigabedialog, müssen Seitenzugriff, Business-Portfolio-Zuweisung und die Meta-App-Berechtigungen geklärt werden. Das Entfernen der Testverbindung allein macht eine bisher nicht freigegebene Seite nicht verfügbar.

## Verwendete Scopes

Instagram erwartet:

- `instagram_business_basic`
- `instagram_business_content_publish`

Facebook erwartet:

- `pages_show_list`
- `pages_read_engagement`
- `pages_manage_posts`

Wenn einer der jeweils benötigten Scopes fehlt, markiert der Health Check nur die betroffene Plattform als `reauth_required`.

## Token-Lifecycle

Die persistierte Baseline ist das User-Token der jeweiligen Plattformverbindung.

Zusätzlich werden pro gefundener Facebook-Seite die zugehörigen `page_access_token`s gespeichert. Diese Tokens werden beim Page-Katalog-Refresh erneut synchronisiert.

`Meta::ConnectionHealthCheck` prüft pro Plattform:

- ob die Verbindung existiert
- ob ein User-Token vorhanden ist
- ob das Token laut gespeichertem Ablaufdatum noch gültig ist
- ob die nötigen Scopes vorhanden sind
- bei Instagram, ob der gespeicherte Instagram-Professional-Account noch passt
- bei Facebook, ob eine ausgewählte Facebook-Seite erreichbar ist

Wenn das gespeicherte User-Token in das Refresh-Fenster läuft, versucht der Health Check serverseitig eine Verlängerung. Bei Facebook wird nach einem erfolgreichen Refresh zusätzlich der Page-Katalog erneut geladen, damit aktuelle Page-Access-Tokens gespeichert bleiben.

## Publishing

Publishing ist ausschließlich zuständig für:

- Laden der aktiven Verbindung der jeweiligen Plattform
- Laden des aktiven Instagram- oder Facebook-Ziels
- Verwenden der gespeicherten IDs und Tokens
- sauberes Scheitern bei `reauth_required`
- Protokollierung des Plattformversuchs

Publishing erzeugt keine Ad-hoc-Tokens und startet keinen interaktiven Login. Instagram-Fehler blockieren Facebook nicht; Facebook-Fehler blockieren Instagram nicht.

Für Instagram-Foto-Posts verwendet die App einen normalen `image_url`-Container ohne `media_type`. In Produktion kann die Instagram-API die eigene App-Domain als Medienquelle ablehnen, obwohl Browser und Facebook-Crawler die Datei abrufen können. Wenn eine Facebook-Seite verbunden ist, verwendet die App deshalb für Instagram-Bilder einen Meta-internen Relay: Das Bild wird als unveröffentlichte Page-Photo hochgeladen, die resultierende Facebook-CDN-URL wird als `image_url` für den Instagram-Container genutzt, und erst danach läuft `media_publish`. Dieser Relay erzeugt keinen Facebook-Post, benötigt aber eine gültige Facebook-Seitenverbindung mit `pages_manage_posts`.
