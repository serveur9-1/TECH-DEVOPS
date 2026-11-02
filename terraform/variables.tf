variable "project_name" {
  description = "Préfixe appliqué au nom et aux étiquettes des ressources."
  type        = string
  default     = "task-manager"
}

variable "aws_region" {
  description = "Région AWS où provisionner la VM."
  type        = string
  default     = "eu-west-3"
}

variable "instance_type" {
  description = "Gabarit de l'instance EC2."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Taille du disque racine, en Gio."
  type        = number
  default     = 20
}

variable "ssh_allowed_cidrs" {
  description = "Plages autorisées à joindre le port 22. Volontairement sans valeur par défaut."
  type        = list(string)

  validation {
    # Le port 22 ouvert au monde entier est la première chose que scannent les
    # robots. Ansible et l'administration passent par une adresse connue.
    condition     = !contains(var.ssh_allowed_cidrs, "0.0.0.0/0")
    error_message = "Le port SSH ne doit pas être ouvert à 0.0.0.0/0 : indiquez votre adresse IP en /32."
  }
}

variable "ssh_public_key_path" {
  description = "Clé publique déposée sur la VM pour l'accès administrateur."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
