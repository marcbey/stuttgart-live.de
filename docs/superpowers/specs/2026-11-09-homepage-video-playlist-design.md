# Startseitenvideos

Am 9. November 2026 von Kathi im Chat freigegeben: Videos spielen in zufällig gemischten Runden, jeder Clip einmal je Runde und ohne direkte Wiederholung am Rundenwechsel. Mobil erscheint unter dem Hauptslider eine Videokachel als erstes Element der horizontalen Highlight-Reihe. Nach Kathis Präzisierung im selben Chat enthält sie ausschließlich Hochformatvideos, zeigt das Bild vollständig in einer schmalen 9:16-Kachel und scrollt mit weg. Unsichtbare Videos pausieren; Ton und Pause bleiben bedienbar. Bestehende Desktop-Positionen bleiben erhalten.

Die vorhandene Stimulus-Videosteuerung erhält eine Playlist mit Quelle, Poster, Eventlink und Beschriftung. Rails liefert nur Metadaten; Videodateien laden erst bei sichtbarer Wiedergabe. Die Auswahl bleibt lokal im Browser, ohne Datenbank- oder Infrastrukturänderung. Bestehende lokale Änderungen bleiben erhalten. Prüfung: JavaScript-Verhalten, Rails-Ausgabe, lokale Design-CI und Browser auf localhost:3000.
