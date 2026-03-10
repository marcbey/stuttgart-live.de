output "app_instance_id" {
  description = "EC2 instance ID for Kamal web role."
  value       = module.app_server.instance_id
}

output "app_public_ip" {
  description = "Elastic IP to use for Kamal SSH/web host."
  value       = aws_eip.app.public_ip
}

output "ecr_repository_url" {
  description = "ECR repository URL used by Kamal."
  value       = module.ecr.repository_url
}

output "ecr_registry_server" {
  description = "ECR registry server host used in Kamal registry.server."
  value       = split("/", module.ecr.repository_url)[0]
}

output "uploads_bucket_name" {
  description = "S3 bucket for production Active Storage uploads."
  value       = module.uploads_bucket.bucket_name
}

output "db_host" {
  description = "RDS hostname."
  value       = var.create_rds ? module.rds[0].address : null
}

output "db_port" {
  description = "RDS port."
  value       = var.create_rds ? module.rds[0].port : null
}

output "app_hostname" {
  description = "Configured app hostname (if Route53 was enabled)."
  value       = var.app_hostname
}
