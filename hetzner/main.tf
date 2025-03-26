terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.50.0"
    }
  }
}

locals {
  count = 4
  valkey_ports = [6379, 7000, 7001, 7002]
}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
  token = var.hcloud_token
}

# Define variables
variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  description = "SSH key name in Hetzner Cloud"
  type        = string
}

variable "server_type" {
  description = "Hetzner Cloud server type"
  type        = string
  default     = "ccx23"  # 2 vCPUs, 4GB RAM - adjust as needed for bigger CPU
}

variable "location" {
  description = "Hetzner Cloud location"
  type        = string
  default     = "nbg1"  # Nuremberg, Germany - adjust as needed
}

# Get SSH key data
data "hcloud_ssh_key" "ssh_key" {
  name = var.ssh_key_name
}

# Create a private network
resource "hcloud_network" "valkey_network" {
  name     = "valkey-network"
  ip_range = "10.0.0.0/16"
}

# Create a subnet
resource "hcloud_network_subnet" "valkey_subnet" {
  network_id   = hcloud_network.valkey_network.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

resource "hcloud_server" "memtier_node" {
  name        = "valkey-benchmark"
  server_type = "ccx33"  # 4 vCPUs, 8GB RAM
  image       = "ubuntu-24.04"
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.ssh_key.id]

  user_data = templatefile("${path.module}/memtier.bash.tpl", {})

  depends_on = [hcloud_server.valkey_nodes]
}

# Create three servers
resource "hcloud_server" "valkey_nodes" {
  count       = local.count
  name        = "valkey-node-${count.index + 1}"
  server_type = var.server_type
  image       = "ubuntu-24.04"
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.ssh_key.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  # Setup script
  user_data = templatefile("${path.module}/setup.tpl", {
    node_index = count.index
    node_count = local.count
    node_ips   = [for i in range(local.count) : join(" ", formatlist("10.0.1.${i + 2}:%d", local.valkey_ports))]
    valkey_ports = join(" ", local.valkey_ports)
  })

  # Wait until the network is ready before creating servers
  depends_on = [hcloud_network_subnet.valkey_subnet]
}

# Attach servers to the network with specific IPs
resource "hcloud_server_network" "valkey_network_config" {
  count      = local.count
  server_id  = hcloud_server.valkey_nodes[count.index].id
  network_id = hcloud_network.valkey_network.id
  ip         = "10.0.1.${count.index + 2}"  # Assign 10.0.1.2, 10.0.1.3, 10.0.1.4
}

resource "hcloud_server_network" "benchmark_network_config" {
  server_id  = hcloud_server.memtier_node.id
  network_id = hcloud_network.valkey_network.id
  ip         = "10.0.1.${local.count + 2}"  # Assign 10.0.1.2, 10.0.1.3, 10.0.1.4
}


# Output information
output "valkey_node_public_ips" {
  value = hcloud_server.valkey_nodes[*].ipv4_address
}

output "benchmark_node_public_ip" {
  value = hcloud_server.memtier_node.ipv4_address
}

output "valkey_node_private_ips" {
  value = [for i in range(local.count) : "10.0.1.${i + 2}"]
}

output "valkey_cluster_info" {
  value = "Valkey cluster is set up with nodes at 10.0.1.2, 10.0.1.3, 10.0.1.4"
}
