variable "github_owner" {
  description = "GitHub-Owner des Repositories."
  type        = string
}

variable "repository" {
  description = "Name des GitHub-Repositories."
  type        = string
}

variable "environment_name" {
  description = "Name des GitHub-Environments."
  type        = string
  default     = "production"
}

variable "app_host" {
  description = "Öffentlicher Hostname für den Kamal-Deploy."
  type        = string
}

variable "kamal_web_host" {
  description = "IPv4 oder Hostname des Zielservers."
  type        = string
}

variable "dotenv_file" {
  description = "Pfad zur .env-Datei mit den Laufzeit- und Deploy-Secrets."
  type        = string
  default     = "../../../../../.env"
}

variable "rails_master_key_file" {
  description = "Pfad zur Rails master.key."
  type        = string
  default     = "../../../../../config/master.key"
}

variable "ssh_private_key_file" {
  description = "Pfad zum privaten SSH-Key für GitHub Deploys."
  type        = string
  default     = "~/.ssh/stgt-live-hetzner-admin"
}
