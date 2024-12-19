provider "aws" {
  region = var.region
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name    = format("project2a-deployment-%s", var.user)
    Owner   = var.user
    Project = "project 2a"
  }
}

resource "aws_internet_gateway" "this" {
  tags = {
    Name    = format("project2a-deployment-%s", var.user)
    Owner   = var.user
    Project = "project 2a"
  }
}

resource "aws_internet_gateway_attachment" "this" {
  internet_gateway_id = aws_internet_gateway.this.id
  vpc_id              = aws_vpc.this.id
}

resource "aws_subnet" "this" {
  vpc_id     = aws_vpc.this.id
  cidr_block = var.subnet_cidr_block

  tags = {
    Name    = format("project-2a-mgmt-%s", var.user)
    Owner   = var.user
    Project = "project 2a"
  }
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Owner   = var.user
    Project = "project 2a"
  }
}

resource "aws_route_table_association" "this" {
  subnet_id      = aws_subnet.this.id
  route_table_id = aws_route_table.this.id
}

resource "aws_security_group" "mgmt" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name    = format("project-2a-mgmt-%s", var.user)
    Owner   = var.user
    Project = "project 2a"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
  security_group_id = aws_security_group.mgmt.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.mgmt.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "allow_kube_api_https" {
  security_group_id = aws_security_group.mgmt.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 6443
  ip_protocol       = "tcp"
  to_port           = 6443
}

resource "aws_key_pair" "mgmt-ssh-key" {
  key_name   = format("project-2a-mgmt-%s", var.user)
  public_key = file("./.keys/ssh-mgmt.pub")
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "p2a-mgmt-yivchenkov" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.management_cluster_instance_type
  subnet_id                   = aws_subnet.this.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.mgmt-ssh-key.key_name
  security_groups = [
    aws_security_group.mgmt.id
  ]

  tags = {
    Name    = format("project2a-deployment-mgmt-%s", var.user)
    Owner   = var.user
    Project = "project 2a"
  }

  depends_on = [aws_internet_gateway.this]
}
