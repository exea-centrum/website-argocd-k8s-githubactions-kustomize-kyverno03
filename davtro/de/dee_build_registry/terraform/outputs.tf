output "repository_name" {
  value = github_repository.website.name
}

output "repository_url" {
  value = github_repository.website.html_url
}

output "clone_url" {
  value = github_repository.website.git_clone_url
}
