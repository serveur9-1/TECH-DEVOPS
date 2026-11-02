# Une seule VM dans le VPC par défaut de la région. Créer un VPC complet
# n'apporterait rien ici : l'application tient sur une instance et n'a aucune
# ressource privée à isoler.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# AMI résolue dynamiquement plutôt que codée en dur : un identifiant d'AMI
# change à chaque région et à chaque publication Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "admin" {
  key_name   = "${var.project_name}-admin"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app"
  description = "Trafic web public, administration SSH restreinte"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  # Une règle par plage : AWS n'accepte qu'un seul CIDR par règle depuis la
  # bascule vers les ressources dédiées.
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "Administration et Ansible"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.app.id
  # Ouvert au monde : c'est aussi par là que passe la validation Let's Encrypt.
  description = "HTTP public et challenge ACME"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS public"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.app.id
  # Sortie libre : le serveur tire les images Docker, les paquets APT et
  # contacte GitHub pour le runner auto-hébergé.
  description = "Sortie libre"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  key_name               = aws_key_pair.admin.key_name
  vpc_security_group_ids = [aws_security_group.app.id]

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    # Les données PostgreSQL vivent sur ce disque : il doit être chiffré.
    encrypted = true
  }

  metadata_options {
    http_endpoint = "enabled"
    # IMDSv2 obligatoire : sans jeton, une SSRF depuis l'application suffirait
    # à lire les identifiants du rôle d'instance.
    http_tokens = "required"
  }

  tags = {
    Name = "${var.project_name}-app"
  }
}

# IP fixe : elle survit à un arrêt/relance de l'instance, ce qui évite de
# refaire pointer le DNS et de perdre le certificat Let's Encrypt.
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-app"
  }
}
