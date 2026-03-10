provider "github" {
  owner = var.github_owner
}

locals {
  dotenv_secret_keys = toset([
    "DB_PASSWORD",
    "EASYTICKET_EVENTS_API",
    "EASYTICKET_EVENT_DETAIL_API",
    "EASYTICKET_PARTNER_SHOP_ID",
    "EASYTICKET_TICKET_LINK_EVENT_BASE_URL",
    "EVENTIM_FEED_URL",
    "EVENTIM_PASS",
    "EVENTIM_USER",
    "KAMAL_REGISTRY_PASSWORD",
    "RESERVIX_API_KEY",
    "RESERVIX_EVENTS_API"
  ])
}

data "external" "dotenv" {
  program = ["ruby", "${path.module}/../../scripts/read_dotenv.rb"]

  query = {
    dotenv_file = var.dotenv_file
    keys_csv    = join(",", sort(tolist(local.dotenv_secret_keys)))
  }
}

locals {
  environment_variables = {
    APP_HOST       = var.app_host
    KAMAL_WEB_HOST = var.kamal_web_host
  }

  dotenv_secrets = {
    for key, value in data.external.dotenv.result :
    key => trimspace(value)
    if trimspace(value) != ""
  }

  file_secrets = merge(
    fileexists(var.rails_master_key_file) ? {
      RAILS_MASTER_KEY = trimspace(file(var.rails_master_key_file))
    } : {},
    fileexists(pathexpand(var.ssh_private_key_file)) ? {
      KAMAL_SSH_PRIVATE_KEY = trimspace(file(pathexpand(var.ssh_private_key_file)))
    } : {}
  )

  environment_secrets = merge(local.dotenv_secrets, local.file_secrets)
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

resource "github_actions_environment_secret" "secrets" {
  for_each = local.environment_secrets

  repository      = var.repository
  environment     = github_repository_environment.production.environment
  secret_name     = each.key
  plaintext_value = each.value
}
