output "firebase_web_config" {
  description = "Public by design: what site/connect/<env>.js carries."
  value       = module.deploy_role.firebase_web_config
}
