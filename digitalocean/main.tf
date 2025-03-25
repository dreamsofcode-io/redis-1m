terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

locals {
  count = 15
}

# Configure the Digital Ocean Provider
provider "digitalocean" {
  token = var.do_token
}

# Define variables
variable "do_token" {
  description = "Digital Ocean API token"
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  description = "Name of SSH key in Digital Ocean"
  type        = string
}

variable "region" {
  description = "Digital Ocean region"
  type        = string
  default     = "nyc1"
}

variable "droplet_size" {
  description = "Droplet size (with 2 vCPUs)"
  type        = string
  default     = "g-2vcpu-8gb-intel"
}

# Get SSH key data
data "digitalocean_ssh_key" "ssh_key" {
  name = var.ssh_key_name
}

# Create a VPC for private network
resource "digitalocean_vpc" "valkey_vpc" {
  name     = "valkey-vpc"
  region   = var.region
  ip_range = "10.10.10.0/24"
}

resource "digitalocean_droplet" "memtier_node" {
  count              = 2
  name               = "valkey-benchmark"
  size               = "c-32-intel"
  image              = "ubuntu-24-04-x64"
  region             = var.region
  vpc_uuid           = digitalocean_vpc.valkey_vpc.id
  ssh_keys           = [data.digitalocean_ssh_key.ssh_key.id]

  depends_on = [
    digitalocean_droplet.valkey_nodes
  ]
  # Setup script
  user_data = templatefile("${path.module}/memtier.bash.tpl", {
  })
}

# Create three droplets
resource "digitalocean_droplet" "valkey_nodes" {
  count              = local.count
  name               = "valkey-node-${count.index + 1}"
  size               = var.droplet_size
  image              = "ubuntu-24-04-x64"
  region             = var.region
  vpc_uuid           = digitalocean_vpc.valkey_vpc.id
  ssh_keys           = [data.digitalocean_ssh_key.ssh_key.id]

  # Setup script
  user_data = templatefile("${path.module}/setup.tpl", {
    node_index = count.index
    node_count = local.count
    node_ips   = [for i in range(local.count) : "10.10.10.${i + 2}:6379"]
  })
}

# Output information
output "valkey_node_public_ips" {
  value = digitalocean_droplet.valkey_nodes[*].ipv4_address
}

output "valkey_node_private_ips" {
  value = digitalocean_droplet.valkey_nodes[*].ipv4_address_private
}

output "memtier" {
  value = digitalocean_droplet.memtier_node[*].ipv4_address
}

output "valkey_cluster_info" {
  value = "Valkey cluster is set up with nodes at ${join(", ", digitalocean_droplet.valkey_nodes[*].ipv4_address_private)}"
}
