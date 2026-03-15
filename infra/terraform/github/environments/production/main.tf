provider "github" {
  owner = var.github_owner
}

resource "github_repository_environment" "production" {
  repository  = var.repository
  environment = var.environment_name
}
