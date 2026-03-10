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

variable "kamal_ssh_host_key" {
  description = "Gepinnte known_hosts-Zeile für den SSH-Host-Key des Zielservers."
  type        = string
}
