output "id" {
  description = "Hetzner-ID der Firewall."
  value       = tonumber(hcloud_firewall.this.id)
}
