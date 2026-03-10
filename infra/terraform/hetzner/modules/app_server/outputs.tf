output "id" {
  description = "Hetzner-ID des Servers."
  value       = hcloud_server.this.id
}

output "name" {
  description = "Servername."
  value       = hcloud_server.this.name
}

output "ipv4_address" {
  description = "Öffentliche IPv4 des Servers."
  value       = try(hcloud_primary_ip.ipv4[0].ip_address, null)
}

output "ipv6_address" {
  description = "Öffentliche IPv6 des Servers."
  value       = try(hcloud_primary_ip.ipv6[0].ip_address, null)
}

output "volume_linux_device" {
  description = "Linux-Device des optionalen Zusatz-Volumes."
  value       = try(hcloud_volume.data[0].linux_device, null)
}
