locals {
  name = var.server_name != "" ? var.server_name : "${var.project}-${var.environment}"

  labels = merge(
    {
      project     = var.project
      environment = var.environment
      managed_by  = "terraform"
      role        = "app"
    },
    var.labels
  )
}

module "ssh_key" {
  source = "../../modules/ssh_key"

  name       = var.ssh_key_name
  public_key = var.ssh_public_key
  labels     = local.labels
}

module "firewall" {
  source = "../../modules/firewall"

  name              = "${local.name}-firewall"
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  labels            = local.labels
}

module "app_server" {
  source = "../../modules/app_server"

  name                      = local.name
  server_type               = var.server_type
  image                     = var.image
  location                  = var.location
  enable_backups            = var.enable_backups
  enable_ipv4               = var.enable_ipv4
  enable_ipv6               = var.enable_ipv6
  enable_delete_protection  = var.enable_delete_protection
  enable_rebuild_protection = var.enable_rebuild_protection
  ssh_key_ids               = [module.ssh_key.id]
  firewall_ids              = [module.firewall.id]
  volume_size               = var.volume_size
  volume_format             = var.volume_format
  labels                    = local.labels
}
