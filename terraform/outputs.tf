output "public_ip" {
  description = "Adresse IP fixe de la VM."
  value       = aws_eip.app.public_ip
}

output "ssh_command" {
  description = "Commande de connexion à la VM."
  value       = "ssh ubuntu@${aws_eip.app.public_ip}"
}

output "application_url" {
  description = "Adresse de l'application une fois Ansible passé."
  value       = "http://${aws_eip.app.public_ip}/"
}

output "ansible_inventory" {
  description = "Inventaire Ansible à écrire dans ansible/inventory.ini."
  value       = <<-EOT
    [app]
    ${aws_eip.app.public_ip} ansible_user=ubuntu
  EOT
}
