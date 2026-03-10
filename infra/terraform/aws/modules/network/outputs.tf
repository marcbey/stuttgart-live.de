output "vpc_id" {
  description = "VPC identifier."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs in index order."
  value       = [for key in sort(keys(aws_subnet.public)) : aws_subnet.public[key].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs in index order."
  value       = [for key in sort(keys(aws_subnet.private)) : aws_subnet.private[key].id]
}
