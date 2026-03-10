output "instance_id" {
  description = "App EC2 instance ID."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "App EC2 public IP (before optional EIP association)."
  value       = aws_instance.this.public_ip
}

output "private_ip" {
  description = "App EC2 private IP."
  value       = aws_instance.this.private_ip
}

output "instance_profile_name" {
  description = "Instance profile name used by EC2."
  value       = aws_iam_instance_profile.this.name
}
