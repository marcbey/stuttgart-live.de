variable "aws_region" {
  description = "AWS region used for production resources."
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "AWS CLI profile (SSO) used by Terraform."
  type        = string
  default     = "stgt-live-admin"
}

variable "project" {
  description = "Project slug used in names/tags."
  type        = string
  default     = "stgt-live"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "Primary VPC CIDR range."
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones used for subnets."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one per AZ)."
  type        = list(string)
  default     = ["10.42.1.0/24", "10.42.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (one per AZ)."
  type        = list(string)
  default     = ["10.42.101.0/24", "10.42.102.0/24"]
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs that may SSH into the app server. Restrict to your fixed IP(s)."
  type        = list(string)
}

variable "key_pair_name" {
  description = "Existing EC2 key pair used by Kamal SSH deploys."
  type        = string
}

variable "ec2_instance_type" {
  description = "EC2 instance type for the app server."
  type        = string
  default     = "t3.small"
}

variable "ec2_ami_id" {
  description = "Optional AMI override. Leave empty to auto-select Ubuntu 24.04."
  type        = string
  default     = ""
}

variable "create_rds" {
  description = "Whether to provision RDS PostgreSQL."
  type        = bool
  default     = true
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Initial RDS storage in GiB."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "RDS max autoscaling storage in GiB."
  type        = number
  default     = 100
}

variable "db_backup_retention_days" {
  description = "RDS backup retention days."
  type        = number
  default     = 7
}

variable "db_name" {
  description = "Application database name."
  type        = string
  default     = "stuttgart_live_de_production"
}

variable "db_username" {
  description = "Application database username."
  type        = string
  default     = "stuttgart_live_de"
}

variable "db_password" {
  description = "Application database password (set via TF_VAR_db_password)."
  type        = string
  sensitive   = true
  default     = null
}

variable "route53_zone_id" {
  description = "Optional Route53 hosted zone ID. Empty disables DNS record creation."
  type        = string
  default     = ""
}

variable "app_hostname" {
  description = "Optional FQDN for app A record (for example live.stuttgart-live.de)."
  type        = string
  default     = ""
}
