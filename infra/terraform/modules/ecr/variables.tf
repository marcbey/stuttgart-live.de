variable "name" {
  description = "ECR repository name."
  type        = string
}

variable "tags" {
  description = "Common tags for ECR resources."
  type        = map(string)
  default     = {}
}
