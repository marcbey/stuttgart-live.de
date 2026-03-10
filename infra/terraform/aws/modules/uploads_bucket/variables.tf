variable "bucket_name" {
  description = "Uploads bucket name. Must be globally unique."
  type        = string
}

variable "tags" {
  description = "Common tags for upload bucket resources."
  type        = map(string)
  default     = {}
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which noncurrent object versions are removed."
  type        = number
  default     = 30
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Days after which incomplete multipart uploads are aborted."
  type        = number
  default     = 7
}
