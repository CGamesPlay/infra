terraform {
  cloud {
    organization = "cgamesplay"

    workspaces {
      tags = ["core"]
    }
  }


  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.35.1"
    }
  }

  required_version = ">= 0.14.9"
}

provider "hcloud" {
}

variable "datacenter" {
  type        = string
  description = "internal name of the target data center"
  default     = "nbg1"
  nullable    = false
}

variable "public_ssh" {
  type        = bool
  description = "enable SSH via public IP"
  default     = true
  nullable    = false
}

variable "delete_protection" {
  type        = bool
  description = "enable delete protection on important resources"
  default     = false
  nullable    = false
}

data "external" "master_user_data" {
  program = ["${path.module}/master_user_data.py"]

  query = {
    # arbitrary map from strings to strings, passed
    # to the external program as the data query.
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
  dynamic "rule" {
    for_each = var.public_ssh ? [1] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = ["0.0.0.0/0", "::/0"]
    }
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51820"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "master" {
  name               = "master"
  image              = "ubuntu-20.04"
  location           = "nbg1"
  server_type        = "cx21"
  user_data          = data.external.master_user_data.result.rendered
  firewall_ids       = [hcloud_firewall.firewall.id]
  rebuild_protection = var.delete_protection
  delete_protection  = var.delete_protection

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

  lifecycle {
    ignore_changes = [ssh_keys, user_data, image]
  }
}

resource "hcloud_volume" "master_drive" {
  name              = "master-drive"
  size              = 20
  server_id         = hcloud_server.master.id
  automount         = false
  format            = "ext4"
  delete_protection = var.delete_protection
}

output "master_ip" {
  description = "Public IP of the master node"
  value       = hcloud_server.master.ipv4_address
}
