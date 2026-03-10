terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

resource "hcloud_primary_ip" "ipv4" {
  count = var.enable_ipv4 ? 1 : 0

  name              = "${var.name}-ipv4"
  type              = "ipv4"
  assignee_type     = "server"
  auto_delete       = true
  delete_protection = var.enable_delete_protection
  location          = var.location
  labels            = var.labels
}

resource "hcloud_primary_ip" "ipv6" {
  count = var.enable_ipv6 ? 1 : 0

  name              = "${var.name}-ipv6"
  type              = "ipv6"
  assignee_type     = "server"
  auto_delete       = true
  delete_protection = var.enable_delete_protection
  location          = var.location
  labels            = var.labels
}

resource "hcloud_server" "this" {
  name               = var.name
  server_type        = var.server_type
  image              = var.image
  location           = var.location
  backups            = var.enable_backups
  delete_protection  = var.enable_delete_protection
  rebuild_protection = var.enable_rebuild_protection
  ssh_keys           = var.ssh_key_ids
  firewall_ids       = var.firewall_ids
  labels             = var.labels
  user_data          = var.user_data

  public_net {
    ipv4_enabled = var.enable_ipv4
    ipv6_enabled = var.enable_ipv6
    ipv4         = var.enable_ipv4 ? tonumber(hcloud_primary_ip.ipv4[0].id) : null
    ipv6         = var.enable_ipv6 ? tonumber(hcloud_primary_ip.ipv6[0].id) : null
  }
}

resource "hcloud_volume" "data" {
  count = var.volume_size > 0 ? 1 : 0

  name              = "${var.name}-data"
  size              = var.volume_size
  format            = var.volume_format
  location          = var.location
  automount         = true
  delete_protection = var.enable_delete_protection
  labels            = var.labels
  server_id         = tonumber(hcloud_server.this.id)
}
