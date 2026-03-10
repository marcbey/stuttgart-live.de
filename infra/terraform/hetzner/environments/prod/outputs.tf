output "server_name" {
  description = "Name des App-Servers."
  value       = module.app_server.name
}

output "server_id" {
  description = "Interne Hetzner-ID des App-Servers."
  value       = module.app_server.id
}

output "server_ipv4" {
  description = "Öffentliche IPv4 des App-Servers."
  value       = module.app_server.ipv4_address
}

output "server_ipv6" {
  description = "Öffentliche IPv6 des App-Servers."
  value       = module.app_server.ipv6_address
}

output "firewall_id" {
  description = "Hetzner-Firewall-ID."
  value       = module.firewall.id
}

output "ssh_key_name" {
  description = "Name des registrierten SSH-Keys."
  value       = module.ssh_key.name
}

output "app_domain" {
  description = "Zieldomain der Anwendung."
  value       = var.app_domain
}

output "volume_linux_device" {
  description = "Linux-Device-Pfad des optionalen Volumes."
  value       = module.app_server.volume_linux_device
}
