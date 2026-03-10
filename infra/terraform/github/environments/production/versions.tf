terraform {
  required_version = ">= 1.8.0"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }

    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}
