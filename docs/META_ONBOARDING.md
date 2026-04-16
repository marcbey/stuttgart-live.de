# Meta-Onboarding und Token-Lifecycle

## Zielbild

`stuttgart-live` verwendet für Social Publishing eine persistierte Meta-Verbindung statt statischer Einmal-Tokens. Das Onboarding verbindet Facebook Page und verknüpften Instagram Professional Account gemeinsam. Operativ publisht das Backend anschließend nur noch direkt zu Instagram; ein optionaler Facebook-Cross-Post wird ausschließlich in Meta konfiguriert.

Die bestehende Instagram-Publish-Logik für die eigentlichen Graph-API-Calls wurde bewusst beibehalten:

- Instagram postet weiter über `/{ig-user-id}/media` und `/{ig-user-id}/media_publish`

Neu strukturiert wurde ausschließlich der Credential-, Onboarding- und Lifecycle-Teil.

## Persistierte Daten

### `social_connections`

Speichert die Meta-Hauptverbindung:

- `provider = meta`
- `auth_mode = facebook_login_for_business`
- verschlüsseltes `user_access_token`
- `user_token_expires_at`
- `granted_scopes`
- `connection_status`
- `connected_at`
- `last_token_check_at`
- `last_refresh_at`
- `reauth_required_at`
- `last_error`

Es gibt bewusst genau eine Meta-Hauptverbindung im System, die bei Re-Auth aktualisiert wird.

### `social_connection_targets`

Speichert die aus dem Onboarding gefundenen Publish-Ziele:

- `target_type = facebook_page` oder `instagram_account`
- `external_id`
- `name` beziehungsweise `username`
- verschlüsseltes `access_token` für Facebook Pages
- `selected`
- `status`
- optionale Parent-Beziehung von Instagram-Target zur gewählten Facebook Page

Damit bleiben mehrere gefundene Pages auswählbar, aber nur eine Page plus ihr verknüpfter Instagram-Account sind aktiv ausgewählt.

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

1. Admin klickt auf `Facebook & Instagram verbinden`.
2. Die App startet `Facebook Login for Business`.
3. Der Callback tauscht den Code serverseitig gegen ein User-Token und danach gegen ein langlebigeres User-Token.
4. Die App lädt die verfügbaren Facebook Pages über `/me/accounts`.
5. Gefundene Pages und verknüpfte Instagram-Accounts werden als `social_connection_targets` persistiert.
6. Im Backend wählt der Admin die gewünschte Facebook Page aus.
7. Die App löst den verknüpften Instagram Professional Account der Page auf und markiert beide Targets als aktiv.

Wenn keine Pages gefunden werden oder keine Instagram-Verknüpfung existiert, bleibt das im Status klar sichtbar und blockiert Publishing.

## Token-Lifecycle

### Baseline

Die persistierte Baseline ist das User-Token der Meta-Verbindung. Das Page-Token wird pro ausgewählter Facebook Page gespeichert und für Publishing verwendet.

### Health Check

`Meta::ConnectionHealthCheck` prüft:

- ob eine Meta-Verbindung existiert
- ob eine Facebook Page ausgewählt ist
- ob das User-Token laut `debug_token` noch gültig ist
- ob die nötigen Scopes vorhanden sind
- ob die gespeicherte Facebook Page noch erreichbar ist
- ob die gespeicherte Instagram-Verknüpfung noch zur Page passt

Dabei werden `social_connections` und ausgewählte Targets laufend aktualisiert.

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

Zusätzlich blockiert ein fehlender Instagram-Professional-Account an der ausgewählten Facebook-Seite das Publishing, auch wenn die Facebook-Seite selbst erreichbar ist.

### Refresh

Wenn das gespeicherte User-Token in das Refresh-Fenster läuft, versucht `Meta::ConnectionHealthCheck` serverseitig eine Verlängerung über den OAuth-Exchange.

Bei Erfolg:

- wird das User-Token aktualisiert
- `last_refresh_at` gesetzt
- der Page-Katalog erneut synchronisiert

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
- Auswahl der Facebook Page
- Auflösung des Instagram-Accounts
- Persistenz der Verbindung und Targets

Publishing ist ausschließlich zuständig für:

- Laden der aktiven Meta-Verbindung
- Laden des Instagram-Ziel-Targets
- Verwenden der gespeicherten IDs und Tokens
- sauberes Scheitern bei `reauth_required`
- Protokollierung der Publish-Versuche

Publishing erzeugt keine Ad-hoc-Tokens mehr und startet auch keinen interaktiven Login.

## Was bewusst erhalten blieb

Die funktionierenden Teile des bisherigen Publish-Flows wurden bewusst nicht neu erfunden:

- bestehende `Meta::InstagramPublisher`-Payload
- vorhandener Draft-, Freigabe- und Publish-Workflow über `EventSocialPost`
- Persistenz der Facebook-Seitenauswahl als Meta-Anker für Instagram

Geändert wurde im Kern nur die Herkunft der Credentials und die Produktionshärtung drumherum.
