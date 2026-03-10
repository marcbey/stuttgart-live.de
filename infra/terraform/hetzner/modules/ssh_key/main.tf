terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

resource "hcloud_ssh_key" "this" {
  name       = var.name
  public_key = trimspace(var.public_key)
  labels     = var.labels
}
