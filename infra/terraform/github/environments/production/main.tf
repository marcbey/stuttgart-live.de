provider "github" {
  owner = var.github_owner
}

locals {
  environment_variables = {
    APP_HOST           = var.app_host
    KAMAL_WEB_HOST     = var.kamal_web_host
    KAMAL_SSH_HOST_KEY = var.kamal_ssh_host_key
  }
}

resource "github_repository_environment" "production" {
  repository  = var.repository
  environment = var.environment_name
}

resource "github_actions_environment_variable" "variables" {
  for_each = {
    for key, value in local.environment_variables :
    key => value
    if trimspace(value) != ""
  }

  repository    = var.repository
  environment   = github_repository_environment.production.environment
  variable_name = each.key
  value         = each.value
}
