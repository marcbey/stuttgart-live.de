# Import & Zusammenführung: Erklärung für die Redaktion

## Worum geht es?

Unsere Eventdaten kommen automatisch von Ticket-Anbietern (z. B. Easyticket, Eventim).
Die Zusammenführung in die finale Eventliste wird im Backend manuell über den Button
"Import-Merge synchronisieren" gestartet.

Das hilft uns, doppelte Events zu vermeiden und Ticketlinks aktuell zu halten.

## Warum sind manche Felder schreibgeschützt?

Einige Felder werden bei jeder automatischen Aktualisierung neu gesetzt.
Damit Redaktionsarbeit nicht ständig "verschwindet", sind diese Felder im Backend als nur-lesbar markiert:

- Artist
- Titel
- Start
- Stadt
- Venue
- Veranstalter
- Promoter-ID

## Welche Felder kann die Redaktion weiterhin pflegen?

Diese Inhalte sind redaktionell und bleiben erhalten:

- Beschreibung
- Redaktionsnotiz
- Banderole
- YouTube-URL
- Genres

## Was passiert mit dem Status bei automatischen Updates?

### `rejected`
Bleibt immer bestehen. Ein abgelehntes Event wird nicht automatisch wieder "hochgestuft".

### Manuell veröffentlicht
Wenn ein Event bewusst durch die Redaktion veröffentlicht wurde, bleibt dieser Veröffentlichungsstatus erhalten.

### Automatisch veröffentlichte Events
Automatisch veröffentlichte Events können bei fehlenden Pflichtdaten wieder auf "prüfen" zurückfallen.

### `needs_review`
Wird gesetzt, wenn wichtige Informationen fehlen (z. B. Bild oder Ticketlink).

## Warum kann sich ein Event nachträglich ändern?

Wenn ein Anbieter seine Daten ändert, wird das beim nächsten Lauf übernommen.
Das betrifft vor allem die importgesteuerten Basisdaten.

## Wozu gibt es mehrere Ticket-Angebote pro Event?

Ein Event kann bei mehreren Ticketshops verfügbar sein.
Darum speichern wir mehrere Angebote pro Event.
Im Frontend wird daraus automatisch der beste verfügbare Ticketlink gewählt.

## Praktische Regel für die Redaktion

- Basisdaten (Artist/Titel/Ort/Start) sind importgesteuert.
- Redaktioneller Mehrwert gehört in Beschreibung, Notizen, Genres und kuratierte Inhalte.
- Wenn ein importiertes Event inhaltlich nicht passt: Status entsprechend setzen (z. B. `rejected`).
