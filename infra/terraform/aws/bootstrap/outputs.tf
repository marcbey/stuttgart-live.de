output "tf_state_bucket" {
  description = "Terraform state bucket name."
  value       = aws_s3_bucket.tf_state.bucket
}

output "tf_lock_table" {
  description = "Terraform lock table name."
  value       = aws_dynamodb_table.tf_lock.name
}
