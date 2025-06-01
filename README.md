# IoT Infrastructure Deployment

Automated deployment system for IoT infrastructure using Terraform, Ansible, and Docker.

## What This Does

- **Deploys a VM** in Proxmox using Terraform
- **Sets up IoT services** with Ansible:
  - TimescaleDB (time-series database)
  - Mosquitto MQTT broker
  - IoT data processing service
- **Manages everything with Docker** containers

## Quick Start

1. **Configure your credentials:**
   ```bash
   # Edit set-proxmox-env.sh with your Proxmox API token
   # Edit ansible/playbooks/timescaledb.yml with your database credentials
   ```

2. **Deploy:**
   ```bash
   ./deploy.sh
   ```

3. **Destroy when done:**
   ```bash
   ./destroy.sh
   ```

## What You Get

- **MQTT Broker** on port 1883
- **TimescaleDB** on port 5432
- **Automated sensor data processing**
- **Real-time data ingestion** from IoT devices

## Requirements

- Proxmox server with API access
- Ansible installed locally
- Terraform installed locally

## Project Structure

```
├── terraform/          # Infrastructure as code
├── ansible/             # Configuration management
├── services/            # Docker services
├── deploy.sh           # One-command deployment
└── destroy.sh          # Clean teardown
```

Perfect for IoT projects that need scalable data collection and storage.