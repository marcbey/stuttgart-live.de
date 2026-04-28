# Meta-Onboarding und Token-Lifecycle

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

## Meta-App-Konfiguration

Die technische Meta-App muss zu `stuttgart-live` passen:

- App-Domain `stuttgart-live.schopp3r.de`
- Website-URL `https://stuttgart-live.schopp3r.de/`
- erlaubte OAuth-Redirect-URL `https://stuttgart-live.schopp3r.de/backend/meta_connection/callback`
- Instagram API with Instagram Login mit `instagram_business_basic` und `instagram_business_content_publish`
- Facebook Login/Login for Business mit `pages_show_list`, `pages_read_engagement` und `pages_manage_posts`

Für Produktion braucht die App Advanced Access/App Review für die Publishing-Scopes. Im Testbetrieb müssen die verwendeten Accounts als Admin, Developer oder Tester der Meta-App berechtigt sein.

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
