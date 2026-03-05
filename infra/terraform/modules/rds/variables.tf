variable "name" {
  description = "Prefix used for resource names."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used by the DB subnet group."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for the RDS instance."
  type        = string
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "allocated_storage" {
  description = "Initial storage size in GiB."
  type        = number
}

variable "max_allocated_storage" {
  description = "Maximum autoscaled storage in GiB."
  type        = number
}

variable "db_name" {
  description = "Primary application database name."
  type        = string
}

variable "db_username" {
  description = "Primary application database user."
  type        = string
}

variable "db_password" {
  description = "Primary application database password."
  type        = string
  sensitive   = true
}

variable "backup_retention_days" {
  description = "Backup retention in days."
  type        = number
}

variable "tags" {
  description = "Common tags for RDS resources."
  type        = map(string)
  default     = {}
}
