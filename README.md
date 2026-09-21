# gcloud-terraform

Deploy a Flask web application on Google Cloud Platform using Terraform.

## Overview

This configuration provisions the following GCP resources:

- **Custom VPC network** (`my-custom-mode-network`) with a subnet in `us-east4` (`10.0.1.0/24`)
- **Compute Engine instance** (`flask-vm`, `f1-micro`, Debian 11) with Flask installed via startup script
- **Firewall rules** — SSH (port 22) and Flask app (port 5000) open to `0.0.0.0/0`

The VM URL is exposed as a Terraform output once provisioned.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- A GCP project with the Compute Engine API enabled
- GCP credentials configured (via `gcloud auth application-default login` or a service account)

## Configuration

In [main.tf](main.tf), replace the placeholder with your GCP project ID:

```hcl
provider "google" {
  project = "YOUR_PROJECT_ID"   # <-- replace this
  region  = "us-east4"
}
```

## Usage

**1. Initialize Terraform** (downloads the Google provider plugin):

```bash
terraform init
```

**2. Preview the changes** before applying:

```bash
terraform plan
```

**3. Apply** to create all resources on GCP:

```bash
terraform apply
```

Type `yes` when prompted. When complete, Terraform prints the Flask app URL:

```
Outputs:

Web-server-URL = "http://<EXTERNAL_IP>:5000"
```

> The VM startup script installs Flask automatically. Allow ~1–2 minutes after `apply` finishes before the app is reachable.

**4. Destroy** all resources when done:

```bash
terraform destroy
```

## Resources Created

| Resource | Name | Details |
|---|---|---|
| VPC Network | `my-custom-mode-network` | Custom mode, MTU 1460 |
| Subnet | `my-custom-subnet` | `10.0.1.0/24`, `us-east4` |
| VM Instance | `flask-vm` | `f1-micro`, `us-east4-a`, Debian 11 |
| Firewall | `allow-ssh` | TCP 22 ingress |
| Firewall | `flask-app-firewall` | TCP 5000 ingress |

## Application

The Flask app ([app.py](app.py)) is deployed separately onto the VM. It serves a single route:

```
GET / → "Hello Cloud!"
```

To run it on the VM after SSH-ing in:

```bash
python3 app.py
```
