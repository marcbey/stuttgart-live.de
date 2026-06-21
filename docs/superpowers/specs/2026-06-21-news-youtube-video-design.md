# News YouTube Video Integration

## Ziel

News-Beiträge sollen optional genau ein YouTube-Video anzeigen können. Redakteure pflegen dafür im Backend eine einzelne YouTube-URL pro News-Beitrag. Öffentlich wird das Video weiterhin nur nach Consent geladen.

## Bestand

`BlogPost` besitzt bereits die JSONB-Spalte `youtube_video_urls` mit Standardwert `[]`. Das Modell normalisiert YouTube-Links bereits auf `https://www.youtube.com/embed/<id>` und entfernt Duplikate. Die öffentliche News-Detailseite rendert bereits einen Consent-geschützten Videoblock, sobald Video-URLs vorhanden sind.

## Umsetzung

- Die bestehende Spalte `youtube_video_urls` bleibt erhalten.
- `BlogPost` bekommt eine redaktionelle Ein-URL-Schnittstelle `youtube_video_url`.
- Der Setter schreibt intern höchstens eine normalisierte URL in `youtube_video_urls`.
- Das Backend-Formular zeigt im News-Tab ein einzelnes Feld `YouTube-URL`.
- Der Controller erlaubt `youtube_video_url` als Parameter.
- Die öffentliche News-Detailseite rendert weiterhin den bestehenden Consent-Video-Partial, aber praktisch nur für die eine gespeicherte URL.

## URL-Regeln

Akzeptiert werden normale YouTube-Video-Links, Kurzlinks und Embed-Links, sofern eine Video-ID ermittelt werden kann. Beispiele:

- `https://www.youtube.com/watch?v=dQw4w9WgXcQ`
- `https://youtu.be/dQw4w9WgXcQ`
- `https://www.youtube.com/embed/dQw4w9WgXcQ`

Leere oder ungültige Werte speichern kein Video.

## Tests

- Modelltest für den neuen Getter/Setter und Normalisierung auf genau eine URL.
- Controller-Test, dass das Backend-Feld gespeichert wird.
- Bestehender öffentlicher News-Test deckt die Consent-Einbettung ab; falls nötig wird er auf die Ein-URL-Schnittstelle umgestellt.

## README

Die Bedienung ändert sich nur um ein kleines redaktionelles Feld. Wenn die Umsetzung keine neuen Betriebs-, Setup- oder Architekturdetails einführt, ist keine README-Änderung erforderlich.
