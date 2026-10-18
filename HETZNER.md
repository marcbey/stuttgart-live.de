# Hetzner-Betrieb

Stand: 18. Oktober 2026

Die aktuelle gemeinsame Architektur von Stuttgart Live und Russ Live steht in
[INFRA.md](INFRA.md). Sie beschreibt Produktion und Staging, Datenbanken, Medien,
GitHub-Freigaben, Rollbacks, die gemeinsame Host-Sperre und offene Betriebsnachweise.

Für konkrete Handgriffe:

- [Deployment und Betrieb in der README](README.md#ci-staging-und-produktionsfreigabe-über-github)
- [Domainwechsel, DNS-Abgleich und Wiederaufnahme nach Fehlern](docs/operations/domainumzug-und-staging.md)
- [Host-Konfiguration mit Ansible](infra/ansible/README.md)
- [Hetzner-Provisionierung mit Terraform](infra/terraform/hetzner/README.md)

Dieses Dokument enthielt ursprünglich die Hosting- und Kostenplanung vom
10. März 2026. Diese Planung ist in der Git-Historie erhalten. Ihre damaligen
Preise, offenen Umsetzungsschritte und direkten Deploy-Kommandos sind keine
aktuelle Betriebsanweisung. Laufende Kosten anhand der tatsächlichen
Hetzner-Ressourcen und Rechnung prüfen.
