# AGENTS.md

## Agent Rules

1. Vor jedem `git push` müssen alle relevanten Linter und Tests erfolgreich durchlaufen.
2. Standardmäßig ist dafür `bin/ci` auszuführen, da dieses Projekt darüber Linting, Security-Checks und die Tests bündelt.
3. Vor jedem `git push` ist der aktuelle Remote-Stand des Zielbranches einzuholen und der lokale Branch per Fast-Forward oder Rebase zu aktualisieren.
4. Nach einem Pull, Fast-Forward oder Rebase muss `bin/ci` erneut erfolgreich durchlaufen, bevor gepusht wird.
5. Ein `git push` ist zu unterlassen, wenn die Aktualisierung des Branches fehlschlägt oder `bin/ci` bzw. einzelne Prüfschritte rot sind.
