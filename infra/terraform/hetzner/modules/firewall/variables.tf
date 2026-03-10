variable "name" {
  description = "Name der Hetzner-Firewall."
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs, die SSH-Zugriff erhalten."
  type        = list(string)
}

variable "labels" {
  description = "Hetzner-Labels."
  type        = map(string)
  default     = {}
}
