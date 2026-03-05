output "app_security_group_id" {
  description = "App security group ID."
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "Database security group ID."
  value       = aws_security_group.db.id
}
