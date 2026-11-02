# VPC dédié : un compte AWS neuf n'a pas toujours de VPC par défaut.
# Un subnet public + une Internet Gateway suffisent ; pas de NAT ni de LB.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "app" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }

  tags = {
    Name = "${var.project_name}-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Résolue dynamiquement : un identifiant d'AMI change à chaque région et à
# chaque publication Canonical.
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
  vpc_id      = aws_vpc.app.id
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  # Une règle par plage : AWS n'accepte qu'un seul CIDR par règle.
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
  # Le serveur tire les images Docker, les paquets APT et contacte GitHub.
  description = "Sortie libre"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = aws_key_pair.admin.key_name
  vpc_security_group_ids = [aws_security_group.app.id]

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    # Les données PostgreSQL vivent sur ce disque.
    encrypted = true
  }

  metadata_options {
    http_endpoint = "enabled"
    # IMDSv2 obligatoire : une SSRF depuis l'application ne suffit plus à lire
    # les identifiants du rôle d'instance.
    http_tokens = "required"
  }

  tags = {
    Name = "${var.project_name}-app"
  }
}

# IP fixe : elle survit à un arrêt/relance de l'instance, donc pas de DNS à
# refaire pointer ni de certificat à redemander.
resource "aws_eip" "app" {
  instance   = aws_instance.app.id
  domain     = "vpc"
  depends_on = [aws_internet_gateway.app]

  tags = {
    Name = "${var.project_name}-app"
  }
}
