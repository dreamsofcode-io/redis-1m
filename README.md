# Redis-1M

A OpenTofu/Terraform-based infrastructure setup for deploying Redis capable of handling up to 1 million operations per second (ops/s) on Hetzner Cloud or DigitalOcean.

## Overview

This repository contains OpenTofu configuration files that automate the deployment of a high-performance Redis infrastructure on Hetzner Cloud or DigitalOcean. It's designed to create a scalable setup capable of handling up to 1 million operations per second, making it suitable for high-throughput applications, load testing, or benchmarking scenarios using memtier_benchmark.

## Features

- Fully automated deployment using OpenTofu/Terraform
- Support for multiple cloud providers (Hetzner Cloud and DigitalOcean)
- Configurable instance types and locations
- Benchmark utilities for testing high throughput using memtier_benchmark
- Easy tear-down process to prevent unwanted billing

## Prerequisites

Before using this repository, make sure you have:

- [OpenTofu](https://opentofu.org/docs/intro/install/) installed (or Terraform)
- An account with either Hetzner Cloud or DigitalOcean
- API token for your chosen cloud provider
- SSH key configured for server access
- Basic understanding of OpenTofu/Terraform and your chosen cloud provider

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/dreamsofcode-io/redis-1m.git
   cd redis-1m
   ```

2. Choose your cloud provider and configure the variables:

   **For Hetzner Cloud**: Create a `terraform.tfvars` file with the following content:
   ```hcl
   hcloud_token = "your_hetzner_api_token"
   ssh_key_name = "your_ssh_key_name"
   
   # Server sizes (uncomment your choice)
   #server_type = "cpx21"   # 2 vCPUs, 4GB RAM
   server_type = "ccx23"    # 4 vCPUs, 8GB RAM
   # server_type = "cpx41"  # 8 vCPUs, 16GB RAM
   # server_type = "cpx51"  # 16 vCPUs, 32GB RAM
   
   # Location options (uncomment your choice)
   location = "nbg1"  # Nuremberg
   # location = "fsn1"  # Falkenstein
   # location = "hel1"  # Helsinki
   # location = "ash"   # Ashburn, VA (US)
   ```

   **For DigitalOcean**: Create a `terraform.tfvars` file with the following content:
   ```hcl
   do_token     = "your_digitalocean_api_token"
   ssh_key_name = "your_ssh_key_name"
   region       = "nyc3"  # New York 3 region
   ```

3. Initialize OpenTofu:
   ```bash
   tofu init
   ```
   Or if using Terraform:
   ```bash
   terraform init
   ```

## Usage

### Deploying the Infrastructure

To deploy the Redis infrastructure:

```bash
tofu apply
```
Or if using Terraform:
```bash
terraform apply
```

Review the planned changes and type `yes` when prompted. The deployment may take a few minutes to complete.

### Running Benchmarks

After deployment, you can use memtier_benchmark to test the Redis performance:

```bash
memtier_benchmark -s [SERVER_IP] -p 6379 --protocol=redis -c 100 -t 10 --pipeline=100 --data-size=32
```

For high throughput testing aiming at 1 million ops/s, you'll need to adjust parameters and possibly use multiple client instances.

### Destroying the Infrastructure

To tear down all created resources and stop billing:

```bash
tofu destroy
```
Or if using Terraform:
```bash
terraform destroy
```

Review the resources to be destroyed and type `yes` when prompted.

## ⚠️ IMPORTANT: Cost Warning

**The cloud resources created by this repository will continue to incur charges until destroyed.**

- Always remember to run `tofu destroy` or `terraform destroy` when you're done with your testing
- Even though Hetzner and DigitalOcean are more cost-effective than some other cloud providers, leaving servers running will still incur charges
- Set reminders or alarms to ensure you don't forget to tear down the infrastructure
- Consider setting up billing alerts in your cloud provider account

## Troubleshooting

Common issues:

1. **Performance Issues**: If you're unable to reach high ops/s counts:
   - Check server CPU and memory utilization
   - Try larger server types
   - Adjust Redis configuration parameters
   - Optimize client benchmark parameters

2. **Network Limitations**: For high throughput:
   - Check network bandwidth between client and server
   - Consider using multiple clients
   - Ensure you're not hitting cloud provider network limits

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[MIT License](LICENSE)
