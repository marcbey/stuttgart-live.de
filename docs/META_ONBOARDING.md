# Meta-Onboarding und Token-Lifecycle

## Zielbild

`stuttgart-live` verwendet für Social Publishing eine persistierte globale Meta-Verbindung statt statischer Einmal-Tokens. Der aktive Standardflow ist wieder **page-fähig**:

- Login über Meta/Facebook Business OAuth
- Auswahl genau einer Facebook-Seite als direktes Facebook-Publish-Ziel
- zugehöriger Instagram-Professional-Account als operatives Instagram-Ziel
- ein Social-Post aus dem Backend veröffentlicht bei aktiver Seitenauswahl direkt auf **Instagram und Facebook**

Bestehende reine `instagram_login`-Verbindungen bleiben lesbar und können weiter **nur Instagram** publishen. Für direktes Facebook-Publishing ist in diesem Fall ein Reconnect im Backend nötig.

## Persistierte Daten

### `social_connections`

Speichert die Meta-Hauptverbindung:

- `provider = meta`
- `auth_mode = facebook_login_for_business` als kanonischer Flow für neue Verbindungen
- verschlüsseltes `user_access_token`
- `user_token_expires_at`
- `granted_scopes`
- `connection_status`
- `connected_at`
- `last_token_check_at`
- `last_refresh_at`
- `reauth_required_at`
- `last_error`

Relevante Metadaten:

- `meta_user_name`
- `last_page_catalog_sync_at`

Historische `instagram_login`-Verbindungen bleiben erhalten und werden im UI als Instagram-only-Verbindungen behandelt.

### `social_connection_targets`

Speichert die aus dem Onboarding gefundenen Ziele:

- `facebook_page` mit `external_id`, `name`, verschlüsseltem `access_token` und Seiten-Metadaten
- `instagram_account` mit `external_id`, `username` und optionaler Verknüpfung zur ausgewählten Seite

Die aktive Facebook-Seite ist global genau ein `selected`-`facebook_page`-Target. Der operative Instagram-Account ist global genau ein `selected`-`instagram_account`-Target.

### `event_social_posts`

Pro Event können wieder zwei operative Publish-Records existieren:

- `instagram` als editierbarer Haupt-Record
- `facebook` als abgeleiteter Spiegel-Record

Der Facebook-Record wird aus dem Instagram-Draft synchronisiert und in v1 nicht separat redaktionell bearbeitet.

### `publish_attempts`

Jeder Plattformversuch wird separat protokolliert mit:

- betroffenem `event_social_post`
- verwendeter `social_connection`
- verwendetem `social_connection_target`
- Start- und Endzeit
- Status `started`, `succeeded` oder `failed`
- Fehlermeldung
- Request-/Response-Snapshot ohne rohe Secrets

## Onboarding-Flow

Der Backend-Einstieg liegt im Settings-Tab `Meta Publishing`.

1. Admin klickt auf `Instagram verbinden`.
2. Die App startet einen Meta-Business-OAuth-Flow über `https://www.facebook.com/v25.0/dialog/oauth`.
3. Der Callback tauscht den Code serverseitig gegen ein Short-lived User-Token.
4. Die App verlängert es direkt zu einem Long-lived User-Token.
5. Danach lädt die App über `me/accounts` alle verwalteten Facebook-Seiten inklusive Page-Access-Token und verknüpftem Instagram-Professional-Account.
6. Die Verbindung wird als `social_connection` persistiert.
7. Die gefundenen Seiten werden als `facebook_page`-Targets gespeichert.
8. Die gefundenen Instagram-Professional-Accounts werden als `instagram_account`-Targets gespeichert.
9. Wenn genau eine passende Facebook-Seite mit verknüpftem Instagram-Professional-Account existiert, wird sie automatisch ausgewählt.
10. Wenn mehrere passende Seiten existieren, bleibt die Verbindung auf `pending_selection`, bis im Backend genau eine Seite ausgewählt wurde.

Wichtig:

- Nur Facebook-Seiten mit verknüpftem Instagram-Professional-Account sind für direktes Facebook-Publishing geeignet.
- Ohne ausgewählte Facebook-Seite bleibt Publishing nur dann zulässig, wenn der operative Instagram-Account trotzdem eindeutig bestimmt werden konnte.

## Erwartete Konfiguration

Für den aktiven Connect-Flow akzeptiert die App diese Credentials oder ENV-Werte:

- bevorzugt `meta.app_id` oder `META_APP_ID`
- bevorzugt `meta.app_secret` oder `META_APP_SECRET`
- optional weiter `meta.instagram_app_id` oder `META_INSTAGRAM_APP_ID`
- optional weiter `meta.instagram_app_secret` oder `META_INSTAGRAM_APP_SECRET`
- optional `meta.instagram_redirect_uri` oder `META_INSTAGRAM_REDIRECT_URI`

Die Instagram-spezifischen Namen bleiben als Fallback lesbar, damit bestehende Setups nicht brechen. Für neue page-fähige Verbindungen sollten aber bevorzugt `meta.app_id` und `meta.app_secret` gesetzt sein.

Wenn `meta.instagram_redirect_uri` gesetzt ist, verwendet die App diese Callback-URL explizit statt die URL aus dem aktuellen Request zu bauen. Der OAuth-Start und der Callback müssen dabei auf demselben Host laufen, weil der `state` serverseitig an die Session gebunden ist.

## Verwendete Scopes

Für den aktuellen Dual-Publish-Use-Case erwartet die App mindestens:

- `pages_show_list`
- `pages_read_engagement`
- `pages_manage_posts`
- `instagram_basic`
- `instagram_content_publish`

Wenn einer dieser Scopes fehlt, markiert der Health Check die Verbindung als `reauth_required` und blockiert Publishing.

## Token-Lifecycle

### Baseline

Die persistierte Baseline ist das Meta-User-Token der Verbindung.

Zusätzlich werden pro gefundener Facebook-Seite die zugehörigen `page_access_token`s gespeichert. Diese Tokens werden beim Page-Katalog-Refresh erneut synchronisiert.

### Health Check

`Meta::ConnectionHealthCheck` prüft für page-fähige Verbindungen:

- ob eine Meta-Verbindung existiert
- ob ein User-Token vorhanden ist
- ob das Token laut gespeichertem Ablaufdatum noch gültig ist
- ob die nötigen Scopes vorhanden sind
- ob der operative Instagram-Account eindeutig bestimmt und noch verfügbar ist
- ob die ausgewählte Facebook-Seite noch erreichbar ist
- ob die ausgewählte Facebook-Seite noch mit dem gespeicherten Instagram-Professional-Account verknüpft ist

Statuslogik:

- ohne ausgewählte Facebook-Seite, aber mit eindeutigem Instagram-Ziel: `pending_selection` als Warnung, Instagram-Publishing bleibt erlaubt
- mit ausgewählter Facebook-Seite: jeder Fehler an Seite, Token oder Verknüpfung blockiert den gesamten Publish

Für historische `instagram_login`-Verbindungen bleibt zusätzlich der alte Instagram-only-Check aktiv.

### Statuswerte

Die Verbindung verwendet diese Zustände:

- `pending_selection`
- `connected`
- `expiring_soon`
- `refresh_failed`
- `reauth_required`
- `revoked`
- `error`

`reauth_required` blockiert Publishing explizit.

### Refresh

Wenn das gespeicherte User-Token in das Refresh-Fenster läuft, versucht `Meta::ConnectionHealthCheck` serverseitig eine Verlängerung über:

- `https://graph.facebook.com/v25.0/oauth/access_token`
- `grant_type=fb_exchange_token`

Nach einem erfolgreichen Refresh wird zusätzlich der Page-Katalog erneut geladen, damit aktuelle Page-Access-Tokens gespeichert bleiben.

## Trennung von Onboarding und Publishing

Onboarding ist ausschließlich zuständig für:

- Login
- Token-Beschaffung
- Laden der verwalteten Facebook-Seiten
- Laden der verknüpften Instagram-Professional-Accounts
- Persistenz der Verbindung und des aktiven Ziels

Publishing ist ausschließlich zuständig für:

- Laden der aktiven Meta-Verbindung
- Laden des aktiven Instagram- und optional des aktiven Facebook-Ziels
- Verwenden der gespeicherten IDs und Tokens
- sauberes Scheitern bei `reauth_required`
- Protokollierung der Publish-Versuche

Publishing erzeugt keine Ad-hoc-Tokens mehr und startet auch keinen interaktiven Login.

## Wichtige Betriebsannahmen

- Ein Social-Post aus dem Backend publiziert bei aktiver Facebook-Seite automatisch zusätzlich direkt auf Facebook.
- Facebook verwendet in v1 denselben Caption-Text und dasselbe Bild wie Instagram.
- Bestehende `instagram_login`-Verbindungen werden nicht automatisch migriert.
- Crossposting über Accounts Center ist kein technischer Bestandteil des Backends mehr und wird nicht vorausgesetzt.
