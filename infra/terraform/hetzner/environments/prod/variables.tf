variable "hcloud_token" {
  description = "Hetzner Cloud API-Token. Kann alternativ über HCLOUD_TOKEN gesetzt werden."
  type        = string
  sensitive   = true
  default     = null
}

variable "project" {
  description = "Projektkürzel für Namen und Labels."
  type        = string
  default     = "stgt-live"
}

variable "environment" {
  description = "Umgebungsname."
  type        = string
  default     = "prod"
}

variable "server_name" {
  description = "Expliziter Servername. Leer lässt Terraform einen Namen aus Projekt und Umgebung bilden."
  type        = string
  default     = ""
}

variable "server_type" {
  description = "Hetzner-Servertyp."
  type        = string
  default     = "cx33"
}

variable "image" {
  description = "Hetzner-Image."
  type        = string
  default     = "ubuntu-24.04"
}

variable "location" {
  description = "Hetzner-Standort, z. B. nbg1 oder fsn1."
  type        = string
  default     = "nbg1"
}

variable "enable_backups" {
  description = "Aktiviert Hetzner Server Backups."
  type        = bool
  default     = true
}

variable "enable_ipv4" {
  description = "Erstellt und hängt eine Primary IPv4 an den Server."
  type        = bool
  default     = true
}

variable "enable_ipv6" {
  description = "Erstellt und hängt eine Primary IPv6 an den Server."
  type        = bool
  default     = true
}

variable "enable_delete_protection" {
  description = "Schützt Server und optionale Zusatzressourcen vor versehentlichem Löschen."
  type        = bool
  default     = true
}

variable "enable_rebuild_protection" {
  description = "Schützt den Server vor versehentlichem Rebuild."
  type        = bool
  default     = true
}

variable "ssh_key_name" {
  description = "Name des bei Hetzner registrierten SSH-Keys."
  type        = string
  default     = "stgt-live-prod"
}

variable "ssh_public_key" {
  description = "Öffentlicher SSH-Key-Inhalt."
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs, die SSH auf den Server dürfen."
  type        = list(string)
}

variable "app_domain" {
  description = "Produktionsdomain der Anwendung."
  type        = string
  default     = "live.stuttgart-live.de"
}

variable "volume_size" {
  description = "Optionales zusätzliches Daten-Volume in GB. 0 deaktiviert das Volume."
  type        = number
  default     = 0
}

variable "volume_format" {
  description = "Dateisystemformat für das optionale Volume."
  type        = string
  default     = "ext4"
}

variable "labels" {
  description = "Zusätzliche Hetzner-Labels."
  type        = map(string)
  default     = {}
}
