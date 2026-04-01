provider "github" {
  owner = var.github_owner
}

resource "github_repository_environment" "production" {
  repository  = var.repository
  environment = var.environment_name
}

resource "github_actions_environment_variable" "variables" {
  for_each = var.environment_variables

  repository    = var.repository
  environment   = github_repository_environment.production.environment
  variable_name = each.key
  value         = each.value
}
