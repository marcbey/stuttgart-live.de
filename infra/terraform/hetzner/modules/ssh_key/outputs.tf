output "id" {
  description = "Hetzner-ID des SSH-Keys."
  value       = hcloud_ssh_key.this.id
}

output "name" {
  description = "Name des SSH-Keys."
  value       = hcloud_ssh_key.this.name
}
