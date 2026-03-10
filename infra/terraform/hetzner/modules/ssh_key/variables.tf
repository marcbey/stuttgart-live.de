variable "name" {
  description = "Name des SSH-Keys bei Hetzner."
  type        = string
}

variable "public_key" {
  description = "Öffentlicher SSH-Key."
  type        = string
}

variable "labels" {
  description = "Hetzner-Labels."
  type        = map(string)
  default     = {}
}
