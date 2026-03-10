variable "name" {
  description = "ECR repository name."
  type        = string
}

variable "tags" {
  description = "Common tags for ECR resources."
  type        = map(string)
  default     = {}
}

variable "max_tagged_images" {
  description = "Maximum number of tagged images to retain."
  type        = number
  default     = 20
}

variable "untagged_image_expiration_days" {
  description = "Days after which untagged images are removed."
  type        = number
  default     = 7
}
