output "bucket_name" {
  description = "Uploads bucket name."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "Uploads bucket ARN."
  value       = aws_s3_bucket.this.arn
}
