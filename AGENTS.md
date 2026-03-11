# AGENTS.md

## Agent Rules

1. Vor jedem `git push` müssen alle relevanten Linter und Tests erfolgreich durchlaufen.
2. Standardmäßig ist dafür `bin/ci` auszuführen, da dieses Projekt darüber Linting, Security-Checks und die Tests bündelt.
3. Ein `git push` ist zu unterlassen, wenn `bin/ci` fehlschlägt oder einzelne Prüfschritte rot sind.
