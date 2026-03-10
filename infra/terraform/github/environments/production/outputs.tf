output "environment_name" {
  description = "Name des verwalteten GitHub-Environments."
  value       = github_repository_environment.production.environment
}

output "environment_variable_names" {
  description = "Alle verwalteten GitHub-Environment-Variablen."
  value       = sort(keys(github_actions_environment_variable.variables))
}
