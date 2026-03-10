output "address" {
  description = "RDS hostname."
  value       = aws_db_instance.this.address
}

output "endpoint" {
  description = "RDS endpoint including port."
  value       = aws_db_instance.this.endpoint
}

output "port" {
  description = "RDS port."
  value       = aws_db_instance.this.port
}
