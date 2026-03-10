variable "name" {
  description = "Prefix used for resource names."
  type        = string
}

variable "vpc_id" {
  description = "Target VPC ID."
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to SSH into app hosts."
  type        = list(string)
}

variable "tags" {
  description = "Common tags for security resources."
  type        = map(string)
  default     = {}
}
