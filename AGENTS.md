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
10. Änderungen an der App, neuen Features, Workflows, Deployments oder Infrastruktur sind immer darauf zu prüfen, ob die `README.md` mitgezogen werden muss. Wenn sich Nutzung, Betrieb, Setup, Architektur, Abhängigkeiten oder Troubleshooting ändern, ist die `README.md` im selben Arbeitsgang zu aktualisieren.
11. Die `README.md` ist in erster Linie für Menschen zu schreiben: klar, verständlich, knapp und praxisnah. Dokumentation soll Zusammenhänge erklären und konkrete Handgriffe benennen, statt nur interne Implementierungsdetails oder Dateilisten abzulegen.

## Skills

Projektlokale Skill-Kopien liegen versioniert unter `./.agents/skills`.

### Available skills

- Rails Conventions & Patterns: Comprehensive Ruby on Rails conventions, design patterns, and idiomatic code standards. Use this skill when writing any Rails code including controllers, models, services, or when making architectural decisions about code organization, naming conventions, and Rails best practices. (file: `./.agents/skills/rails-conventions-patterns/SKILL.md`)
- Ruby OOP Patterns: Comprehensive guide to Object-Oriented Programming in Ruby and Rails covering classes, modules, design patterns, SOLID principles, and modern Ruby 3.x features. (file: `./.agents/skills/ruby-oop-patterns/SKILL.md`)
- Turbo & Hotwire Patterns: Complete guide to Hotwire implementation including Turbo Drive, Turbo Frames, Turbo Streams, and Stimulus controllers in Rails applications. Use this skill when implementing real-time updates, partial page rendering, or JavaScript behaviors in Rails views. (file: `./.agents/skills/turbo-hotwire-patterns/SKILL.md`)
- gh-address-comments: Help address review or issue comments on the open GitHub PR for the current branch using `gh` CLI; verify `gh` auth first and prompt the user to authenticate if not logged in. (file: `./.agents/skills/gh-address-comments/SKILL.md`)
- git-commit: Execute git commit with conventional commit message analysis, intelligent staging, and message generation. Use when the user asks to commit changes, create a git commit, or mentions `/commit`. (file: `./.agents/skills/git-commit/SKILL.md`)
- playwright: Use when the task requires automating a real browser from the terminal via `playwright-cli` or the bundled wrapper script. (file: `./.agents/skills/playwright/SKILL.md`)
- screenshot: Use when the user explicitly asks for a desktop or system screenshot, or when tool-specific capture capabilities are unavailable and an OS-level capture is needed. (file: `./.agents/skills/screenshot/SKILL.md`)
- web-design-guidelines: Review UI code for Web Interface Guidelines compliance. Use when asked to review UI, accessibility, design, or UX against best practices. (file: `./.agents/skills/web-design-guidelines/SKILL.md`)

### How to use skills

- Discovery: The list above is the skill inventory intended for this repository. Skill bodies live on disk at the listed paths.
- Trigger rules: If the user names a skill with `$SkillName` or plain text, or the task clearly matches a skill's description, that skill must be used for the turn. Multiple mentions mean use them all. Do not carry skills across turns unless they are re-mentioned.
- Missing or blocked: If a named skill cannot be read cleanly, say so briefly and continue with the best fallback.
- How to use a skill: Open the skill's `SKILL.md`, read only enough to follow the workflow, resolve relative paths from the skill directory first, and only load extra references, scripts, or assets when needed.
- Coordination: Choose the minimal skill set that covers the request and state the order if multiple skills apply.
- Context hygiene: Keep context small, summarize long sections, and avoid deep reference-chasing unless blocked.
- Safety and fallback: If a skill cannot be applied cleanly, state the issue, pick the next-best approach, and continue.
