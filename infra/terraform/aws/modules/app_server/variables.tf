variable "name" {
  description = "Prefix used for resource names."
  type        = string
}

variable "ami_id" {
  description = "Optional AMI ID override. Leave empty to auto-select Ubuntu 24.04 LTS."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type for the app host."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the app host."
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the app host."
  type        = string
}

variable "key_pair_name" {
  description = "Existing EC2 key pair for SSH/Kamal access."
  type        = string
}

variable "additional_policy_arns" {
  description = "Extra IAM policy ARNs attached to the EC2 role."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Common tags for app resources."
  type        = map(string)
  default     = {}
}
