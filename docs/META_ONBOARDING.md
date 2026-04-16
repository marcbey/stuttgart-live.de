# Meta-Onboarding und Token-Lifecycle

## Zielbild

`stuttgart-live` verwendet für Social Publishing eine persistierte Meta-Verbindung statt statischer Einmal-Tokens. Das Onboarding ist jetzt **Instagram-first** und nutzt **Instagram API with Instagram Login**. Operativ publisht das Backend anschließend nur noch direkt zu Instagram. Ein optionaler Facebook-Cross-Post wird ausschließlich im verbundenen Meta-Konto konfiguriert und von der App weder geprüft noch gesteuert.

Die eigentliche Publish-Logik bleibt bewusst schlank:

- Instagram postet weiter über `/{ig-user-id}/media` und `/{ig-user-id}/media_publish`
- der API-Host ist dafür `graph.instagram.com`
- verwendet wird ein persistiertes **Instagram User access token**

## Persistierte Daten

### `social_connections`

Speichert die Meta-Hauptverbindung:

- `provider = meta`
- `auth_mode = instagram_login` für neue Verbindungen
- verschlüsseltes `user_access_token`
- `user_token_expires_at`
- `granted_scopes`
- `connection_status`
- `connected_at`
- `last_token_check_at`
- `last_refresh_at`
- `reauth_required_at`
- `last_error`

`facebook_login_for_business` bleibt nur noch als Legacy-Modus für Altverbindungen lesbar.

Zusätzliche Metadaten für den neuen Flow:

- `instagram_user_id`
- `instagram_username`
- `instagram_account_type`
- `last_instagram_sync_at`

### `social_connection_targets`

Speichert die aus dem Onboarding gefundenen Publish-Ziele:

- `target_type = instagram_account` als operatives Ziel
- `external_id` = Instagram Professional Account ID
- `username` und optional `name`
- `selected`
- `status`

Historische `facebook_page`-Targets können für Legacy-Verbindungen weiter existieren, werden für neue Verbindungen aber nicht mehr angelegt.

### Bestehende `event_social_posts`

`event_social_posts` bleiben die eigentlichen Publish-Records. Operativ wird nur noch der `instagram`-Record aktiv verwendet:

- ein Record für `instagram`

Historische `facebook`-Records können in der Datenbank verbleiben, werden aber im Backend weder neu erzeugt noch für Status, UI oder Publishing herangezogen. `Event#social_publication_status` spiegelt deshalb nur noch den Zustand des Instagram-Posts.

### `publish_attempts`

Jeder Publish-Versuch wird separat protokolliert mit:

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
2. Die App startet den OAuth-Flow über `https://www.instagram.com/oauth/authorize`.
3. Der Callback tauscht den Code serverseitig gegen ein Short-lived User-Token.
4. Die App tauscht dieses Token direkt gegen ein Long-lived Instagram User access token.
5. Danach lädt die App den verbundenen Instagram-Professional-Account über `/me`.
6. Die Verbindung wird als `social_connection` persistiert.
7. Der gefundene Instagram-Account wird als einziges aktives `instagram_account`-Target gespeichert und ausgewählt.

Es gibt im Standardflow **keine Facebook-Seitenauswahl mehr**.

## Erwartete Konfiguration

Für den aktuellen Instagram-Login-Flow liest die App bevorzugt diese Credentials oder ENV-Werte:

- `meta.instagram_app_id` oder `META_INSTAGRAM_APP_ID`
- `meta.instagram_app_secret` oder `META_INSTAGRAM_APP_SECRET`
- `meta.instagram_redirect_uri` oder `META_INSTAGRAM_REDIRECT_URI`

Zur Rückwärtskompatibilität akzeptiert die App vorerst auch noch:

- `meta.app_id` oder `META_APP_ID`
- `meta.app_secret` oder `META_APP_SECRET`

Die neuen Instagram-spezifischen Namen sollten aber bevorzugt werden, damit die Werte nicht mehr mit dem alten Facebook-Login-Flow verwechselt werden.

Wenn `meta.instagram_redirect_uri` gesetzt ist, verwendet die App diese Callback-URL explizit statt die URL aus dem aktuellen Request zu bauen. Das ist nützlich, wenn der OAuth-Start lokal ausgelöst wird, der Meta-Callback aber bewusst auf eine feste HTTPS-Domain wie `https://stuttgart-live.schopp3r.de/backend/meta_connection/callback` zurücklaufen soll.

Wichtig: Der OAuth-Start und der Callback müssen dabei auf demselben Host laufen, weil der `state` serverseitig an die Session gebunden ist. Wenn `meta.instagram_redirect_uri` auf `https://stuttgart-live.schopp3r.de/...` zeigt, muss der Connect-Flow deshalb auch auf genau diesem Host gestartet werden und nicht auf `localhost`.

## Verwendete Scopes

Für den aktuellen Publishing-Use-Case erwartet die App mindestens:

- `instagram_business_basic`
- `instagram_business_content_publish`

Wenn einer dieser Scopes fehlt, markiert der Health Check die Verbindung als `reauth_required` und blockiert Publishing.

## Token-Lifecycle

### Baseline

Die persistierte Baseline ist das Instagram User access token der Verbindung. Page-Tokens werden im neuen Flow nicht mehr benötigt.

### Health Check

`Meta::ConnectionHealthCheck` prüft im `instagram_login`-Modus:

- ob eine Meta-Verbindung existiert
- ob ein User-Token vorhanden ist
- ob das Token laut gespeichertem Ablaufdatum noch gültig ist
- ob die nötigen Scopes vorhanden sind
- ob der Instagram-Professional-Account über `/me` erreichbar ist
- ob der Account-Typ `BUSINESS` oder `MEDIA_CREATOR` ist
- ob das gespeicherte Instagram-Ziel noch mit dem verbundenen Account übereinstimmt

Für Legacy-Verbindungen mit `facebook_login_for_business` bleibt zusätzlich der alte Check gegen Facebook-Seite und `instagram_business_account` aktiv.

### Statuswerte

Die Verbindung verwendet klar definierte Zustände:

- `pending_selection`
- `connected`
- `expiring_soon`
- `refresh_failed`
- `reauth_required`
- `revoked`
- `error`

`reauth_required` blockiert Publishing bewusst explizit.

### Refresh

Wenn das gespeicherte User-Token in das Refresh-Fenster läuft, versucht `Meta::ConnectionHealthCheck` serverseitig eine Verlängerung.

Für `instagram_login` läuft das über:

- `https://graph.instagram.com/refresh_access_token`
- `grant_type=ig_refresh_token`

Das Long-lived Token ist laut Meta typischerweise 60 Tage gültig und kann erneuert werden, solange es noch gültig und älter als 24 Stunden ist.

Bei Erfolg:

- wird das User-Token aktualisiert
- `last_refresh_at` gesetzt

Bei Fehlschlag:

- wechselt der Verbindungsstatus auf `refresh_failed`
- der Fehler wird gespeichert
- Publishing bleibt nur so lange möglich, wie die Live-Prüfung noch erfolgreich ist

### Scheduling

Der regelmäßige Check läuft über:

- `Meta::CheckConnectionHealthJob`
- konfiguriert in `config/recurring.yml`

## Trennung von Onboarding und Publishing

Onboarding ist ausschließlich zuständig für:

- Login
- Token-Beschaffung
- Laden des verbundenen Instagram-Accounts
- Persistenz der Verbindung und des aktiven Targets

Publishing ist ausschließlich zuständig für:

- Laden der aktiven Meta-Verbindung
- Laden des Instagram-Ziel-Targets
- Verwenden der gespeicherten IDs und Tokens
- sauberes Scheitern bei `reauth_required`
- Protokollierung der Publish-Versuche

Publishing erzeugt keine Ad-hoc-Tokens mehr und startet auch keinen interaktiven Login.

## Legacy-Kompatibilität

Bestehende `facebook_login_for_business`-Verbindungen bleiben vorerst lesbar:

- die Legacy-Facebook-Seitenauswahl bleibt für diese Verbindungen sichtbar
- neue Verbindungen laufen aber ausschließlich über `instagram_login`
- direkte Facebook-Seitenlogik ist kein Teil des Standard-Onboardings mehr

## Wichtige Betriebsannahmen

- Die App veröffentlicht nur noch direkt zu Instagram.
- Ob Instagram-Posts zusätzlich nach Facebook geteilt werden, bleibt eine reine Meta-Kontoeinstellung.
- Eine Facebook-Seite ist für neue Verbindungen **keine Onboarding-Voraussetzung** mehr.
- Ein möglicher PPA-Fehler auf Meta-Seite bleibt ein Laufzeitproblem beim Publish, kein Onboarding-Schritt der App.
