variable "bucket_name" {
  description = "Uploads bucket name. Must be globally unique."
  type        = string
}

variable "tags" {
  description = "Common tags for upload bucket resources."
  type        = map(string)
  default     = {}
}
