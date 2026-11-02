output "public_ip" {
  description = "Adresse IP fixe de la VM."
  value       = aws_eip.app.public_ip
}

output "ssh_command" {
  description = "Commande de connexion à la VM."
  value       = "ssh ubuntu@${aws_eip.app.public_ip}"
}

output "application_url" {
  description = "Adresse HTTP de l'application."
  value       = "http://${aws_eip.app.public_ip}/"
}

output "security_group_id" {
  description = "Security group à renseigner dans le secret GitHub EC2_SECURITY_GROUP_ID."
  value       = aws_security_group.app.id
}
