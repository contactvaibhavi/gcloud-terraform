# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository provisions a GCP environment using Terraform and configures it with Ansible. There are two separate Terraform configurations:

- [main.tf](main.tf) — deploys a Flask VM with a custom VPC/subnet and firewall rules for SSH (port 22) and Flask (port 5000). Uses inline `metadata_startup_script` to install Flask. Outputs the public URL.
- [ansible/vpc.tf](ansible/vpc.tf) — an alternative Terraform config that provisions a VM with a static external IP and generates an Ansible inventory file from [ansible/clusterinventory.tpl](ansible/clusterinventory.tpl).

The Ansible playbook ([ansible/packages.yaml](ansible/packages.yaml)) installs networking tools (`wget`, `iperf`, `iperf3`) on the provisioned server.

The Flask app ([app.py](app.py)) is a minimal single-route app that runs on `0.0.0.0:5000`.

## Prerequisites

- Terraform CLI
- GCP credentials (`key.json` for `ansible/vpc.tf`; ADC or service account for `main.tf`)
- Ansible (for `ansible/packages.yaml`)

## Terraform Commands

```bash
terraform init
terraform plan
terraform apply
terraform destroy
```

For the `ansible/` config, run these from inside the `ansible/` directory.

## Configuration Required Before Use

**main.tf**: Replace `YOUR_PROJECT_ID` with your GCP project ID.

**ansible/vpc.tf**: Replace placeholder values:
- `<YOUR HOME DIR>` — path to your SSH keys
- `<YOUR ID on VM>` — SSH username for the VM
- `<YOUR GCP PROJECT NAME>` — GCP project name
- Place a `key.json` GCP service account credentials file in the `ansible/` directory

## Ansible

After `terraform apply` in `ansible/`, a `cluster.inventory` file is generated automatically. Run the playbook with:

```bash
ansible-playbook -i ansible/cluster.inventory ansible/packages.yaml
```
