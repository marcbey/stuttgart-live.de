output "environment_name" {
  description = "Name des verwalteten GitHub-Environments."
  value       = github_repository_environment.production.environment
}
