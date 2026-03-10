terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

locals {
  internet_cidrs = ["0.0.0.0/0", "::/0"]
}

resource "hcloud_firewall" "this" {
  name   = var.name
  labels = var.labels

  rule {
    description = "SSH"
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = var.allowed_ssh_cidrs
  }

  rule {
    description = "HTTP"
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = local.internet_cidrs
  }

  rule {
    description = "HTTPS"
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = local.internet_cidrs
  }

  rule {
    description = "ICMP in"
    direction   = "in"
    protocol    = "icmp"
    source_ips  = local.internet_cidrs
  }

  rule {
    description     = "TCP out"
    direction       = "out"
    protocol        = "tcp"
    destination_ips = local.internet_cidrs
  }

  rule {
    description     = "UDP out"
    direction       = "out"
    protocol        = "udp"
    destination_ips = local.internet_cidrs
  }

  rule {
    description     = "ICMP out"
    direction       = "out"
    protocol        = "icmp"
    destination_ips = local.internet_cidrs
  }
}
