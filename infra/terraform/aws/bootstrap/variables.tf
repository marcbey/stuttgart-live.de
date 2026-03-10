variable "aws_region" {
  description = "AWS region for bootstrap resources."
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "AWS CLI profile (SSO) used by Terraform."
  type        = string
  default     = "stgt-live-admin"
}

variable "tf_state_bucket" {
  description = "S3 bucket name for Terraform remote state. Must be globally unique."
  type        = string
}

variable "tf_lock_table" {
  description = "DynamoDB table name for Terraform state locking."
  type        = string
  default     = "stgt-live-terraform-locks"
}

variable "tags" {
  description = "Extra tags for bootstrap resources."
  type        = map(string)
  default     = {}
}
