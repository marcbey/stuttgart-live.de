variable "name" {
  description = "Servername."
  type        = string
}

variable "server_type" {
  description = "Hetzner-Servertyp."
  type        = string
}

variable "image" {
  description = "Hetzner-Image."
  type        = string
}

variable "location" {
  description = "Hetzner-Standort."
  type        = string
}

variable "enable_backups" {
  description = "Aktiviert Server Backups."
  type        = bool
  default     = true
}

variable "enable_ipv4" {
  description = "Aktiviert eine Primary IPv4."
  type        = bool
  default     = true
}

variable "enable_ipv6" {
  description = "Aktiviert eine Primary IPv6."
  type        = bool
  default     = true
}

variable "enable_delete_protection" {
  description = "Aktiviert Delete Protection."
  type        = bool
  default     = true
}

variable "enable_rebuild_protection" {
  description = "Aktiviert Rebuild Protection."
  type        = bool
  default     = true
}

variable "ssh_key_ids" {
  description = "IDs der SSH-Keys für den Initialzugriff."
  type        = list(string)
}

variable "firewall_ids" {
  description = "IDs der an den Server zu bindenden Firewalls."
  type        = list(number)
  default     = []
}

variable "volume_size" {
  description = "Optionales Zusatz-Volume in GB. 0 deaktiviert das Volume."
  type        = number
  default     = 0
}

variable "volume_format" {
  description = "Dateisystemformat für das Zusatz-Volume."
  type        = string
  default     = "ext4"
}

variable "labels" {
  description = "Hetzner-Labels."
  type        = map(string)
  default     = {}
}

variable "user_data" {
  description = "Optionales Cloud-Init-User-Data."
  type        = string
  default     = null
}
