terraform {
  backend "s3" {
    bucket = "infra-029993131878"
    key    = "terraform"
    region = "eu-central-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

variable "aws_region" {
  type = string
  description = "region which will be used for all infrastructure"
  default = "eu-central-1"
}

variable "aws_az" {
  type = string
  description = "availability zone which will be used for all infrastructure"
  default = "eu-central-1a"
}

variable "aws_keypair_name" {
  type = string
  description = "keypair which will be used for all instances"
}

provider "aws" {
  profile = "default"
  region  = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.*-arm64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_security_group" "web" {
  name   = "web"
  vpc_id = aws_default_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SSH and HTTP"
  }
}

data "template_cloudinit_config" "master_cloudinit" {
  part {
    content_type = "text/cloud-config"
    content      = file("master_user_data.yaml")
  }
}

resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t4g.nano"
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = data.template_cloudinit_config.master_cloudinit.rendered
  key_name = var.aws_keypair_name

  tags = {
    Name = "master"
  }

  root_block_device {
    volume_type = "gp3"
  }
}

output "master_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.master.public_ip
}
