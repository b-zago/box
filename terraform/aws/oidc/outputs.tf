output "providers" {
  value = { for k, v in module.providers : k => v.role_arn }
}
