terraform {
  backend "s3" {
    bucket = "infra-029993131878"
    key    = "terraform"
    region = "eu-central-1"
  }

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.26.0"
    }
  }

  required_version = ">= 0.14.9"
}

provider "hcloud" {
  token = var.hcloud_token
}

variable "hcloud_token" {
  type        = string
  description = "token for use with hcloud"
}

variable "hcloud_key_name" {
  type        = string
  description = "keypair which will be used for all hcloud instances"
}

data "template_cloudinit_config" "master_cloudinit" {
  part {
    content_type = "text/cloud-config"
    content      = file("master_user_data.yaml")
  }
}

resource "hcloud_network" "network" {
  name     = "network"
  ip_range = "172.31.0.0/16"
}

resource "hcloud_network_subnet" "network_subnet" {
  type         = "cloud"
  network_id   = hcloud_network.network.id
  network_zone = "eu-central"
  ip_range     = "172.31.0.0/20"
}

resource "hcloud_firewall" "firewall" {
  name = "firewall"
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction = "in"
    protocol = "tcp"
    port = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction = "in"
    protocol = "tcp"
    port = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction = "in"
    protocol = "udp"
    port = "51820"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "master" {
  name         = "master"
  image        = "ubuntu-20.04"
  location     = "nbg1"
  server_type  = "cx21"
  ssh_keys     = [var.hcloud_key_name]
  user_data    = data.template_cloudinit_config.master_cloudinit.rendered
  firewall_ids = [hcloud_firewall.firewall.id]

  network {
    network_id = hcloud_network.network.id
    ip         = "172.31.0.2"
  }

  # Note: the depends_on is important when directly attaching the server to a
  # network. Otherwise Terraform will attempt to create server and sub-network
  # in parallel. This may result in the server creation failing randomly.
  depends_on = [
    hcloud_network_subnet.network_subnet
  ]
}

output "master_ip" {
  description = "Public IP of the master node"
  value       = hcloud_server.master.ipv4_address
}
