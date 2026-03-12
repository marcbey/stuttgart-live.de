# AGENTS.md

## Schreibweise

- Verwende in deutschsprachigen Texten und Dokumentationen echte Umlaute (`ä`, `ö`, `ü`, `Ä`, `Ö`, `Ü`) sowie `ß` statt ASCII-Umschreibungen wie `ae`, `oe`, `ue`, `ss`, sofern das Dateiformat und der Kontext UTF-8 zulassen.

## Agent Rules

1. Vor jedem `git push` müssen alle relevanten Linter und Tests erfolgreich durchlaufen.
2. Standardmäßig ist dafür `bin/ci` auszuführen, da dieses Projekt darüber Linting, Security-Checks und die Tests bündelt.
3. Vor jedem `git push` ist der aktuelle Remote-Stand des Zielbranches einzuholen und der lokale Branch per Fast-Forward oder Rebase zu aktualisieren.
4. Nach einem Pull, Fast-Forward oder Rebase muss `bin/ci` erneut erfolgreich durchlaufen, bevor gepusht wird.
5. Ein `git push` ist zu unterlassen, wenn die Aktualisierung des Branches fehlschlägt oder `bin/ci` bzw. einzelne Prüfschritte rot sind.
6. Wenn nach `git pull`, Rebase oder Branch-Wechsel neue Migrationen ins Arbeitsverzeichnis kommen, muss die lokale Datenbank vor weiteren Tests, App-Starts oder Deploy-Schritten auf den aktuellen Stand gebracht werden.
7. Standardmäßig ist dafür das im Projekt vorgesehene Kommando zu verwenden, bevorzugt `bin/rails db:migrate` oder `bin/setup`, sofern dieses die Migrationen zuverlässig mit ausführt.
8. Bei Änderungen, neuen Seiten oder neuen Features im öffentlich zugänglichen Bereich ohne Login ist Barrierefreiheit von Anfang an mitzudenken. Ziel ist WCAG 2.2 AA: Semantik, Tastaturbedienbarkeit, sichtbarer Fokus, ausreichende Kontraste, verständliche Formularbeschriftungen, sinnvolle ARIA-Nutzung und screenreadertaugliche dynamische Zustände sind bei Umsetzung und Review mit zu prüfen.

9. Bei Änderungen, neuen Seiten oder neuen Features im öffentlich zugänglichen Bereich ohne Login ist SEO ebenfalls von Anfang an mitzudenken. Dazu gehören insbesondere sinnvolle Seitentitel, Meta-Descriptions, klare Überschriftenstruktur, indexierbare Inhalte, sprechende interne Verlinkung, Canonical-URLs, aussagekräftige Linktexte sowie technisch saubere Metadaten für Suchmaschinen und Social Sharing.
