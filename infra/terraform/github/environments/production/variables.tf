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
