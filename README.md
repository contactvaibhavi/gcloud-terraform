# gcloud-terraform

Provision Google Cloud Compute Engine with Terraform, configure hosts with Ansible, and run a minimal Flask service.

This repository contains two independent lab tracks. Use **Track A** for a custom VPC and Flask demo. Use **Track B** for Terraform-generated Ansible inventory and package installation. Do not mix resources from the two tracks unless you intentionally redesign the stack.

| Path | Purpose |
|------|---------|
| [`main.tf`](main.tf) | Track A: custom VPC, subnet, firewall, Debian VM, Flask via startup script |
| [`app.py`](app.py) | Flask app: `GET /` returns `Hello Cloud!` |
| [`ansible/vpc.tf`](ansible/vpc.tf) | Track B: VM on the default network, static IP, SSH metadata, inventory file |
| [`ansible/clusterinventory.tpl`](ansible/clusterinventory.tpl) | Template rendered to `cluster.inventory` |
| [`ansible/packages.yaml`](ansible/packages.yaml) | Ansible playbook: install `wget`, `iperf`, `iperf3` |

---

## Prerequisites

- GCP project with the Compute Engine API enabled
- Track A: Application Default Credentials for the Google provider — run `gcloud auth application-default login` (ordinary `gcloud auth login` alone is not enough for Terraform). Track B: service-account key at `ansible/key.json` (required by the current provider configuration)
- Terraform ≥ 1.x
- Python 3 and `pip`
- Ansible (Track B only)
- SSH keypair (Track B only)

Replace placeholders before `terraform apply`:

| Placeholder | File |
|-------------|------|
| `YOUR_PROJECT_ID` | `main.tf` |
| `<YOUR GCP PROJECT ID>` | `ansible/vpc.tf` |
| `<YOUR HOME DIR>/.ssh/id_rsa` and `.pub` | `ansible/vpc.tf` |
| `<YOUR ID on VM>` | `ansible/vpc.tf` |
| `key.json` (service-account key path) | `ansible/vpc.tf` |

---

## Architecture

```text
Track A (repository root)
  Terraform → custom VPC + subnet (10.0.1.0/24, us-east4)
           → firewall: TCP 22 (tag ssh), TCP 5000
           → f1-micro VM (debian-11), startup: install Flask
           → output Web-server-URL = http://<EXTERNAL_IP>:5000
  You still must copy and run app.py on the VM.

Track B (ansible/)
  Terraform → static external IP
           → n1-standard-1 VM (debian-10) on default VPC
           → SSH public key in instance metadata
           → write cluster.inventory
  Ansible  → apt install wget, iperf, iperf3
```

Both tracks use `us-east4` / `us-east4-a`. They differ in machine type, OS image, network model, and post-provisioning.

---

## Track A — Flask on a custom VPC

### Apply infrastructure

```bash
# edit project in main.tf first
terraform init
terraform plan
terraform apply
terraform output Web-server-URL
```

This creates the VPC, subnet, instance `flask-vm`, and firewall rules, and installs the Flask package on first boot. It does **not** deploy or start `app.py`.

### Run the application

Local check (no GCP):

```bash
pip install flask
python3 app.py
curl http://127.0.0.1:5000/
```

On the VM after apply:

```bash
gcloud compute ssh flask-vm --zone=us-east4-a
# copy app.py to the instance (scp / gcloud compute scp), then:
python3 app.py
```

From your laptop:

```bash
curl "$(terraform output -raw Web-server-URL)"
# expected: Hello Cloud!
```

### Tear down

```bash
terraform destroy
```

---

## Track B — Terraform inventory + Ansible

### Apply infrastructure

```bash
cd ansible
# place service-account JSON as key.json (do not commit it)
# set ssh_key, ssh_private_key, ssh_user, and project in vpc.tf
terraform init
terraform apply
cat cluster.inventory
```

Outputs: `instance_ip` (private), `instance_fip` (public). Inventory group `[server]` uses the public IP.

### Configure the host

```bash
ansible-playbook -i cluster.inventory packages.yaml
```

### Tear down

```bash
terraform destroy
```

---

## Resources created

### Track A (`main.tf`)

| Resource | Details |
|----------|---------|
| `google_compute_network` | `my-custom-mode-network`, custom mode, MTU 1460 |
| `google_compute_subnetwork` | `my-custom-subnet`, `10.0.1.0/24`, `us-east4` |
| `google_compute_instance` | `flask-vm`, `f1-micro`, `us-east4-a`, tag `ssh`, debian-11 |
| `google_compute_firewall` | `allow-ssh`: TCP 22 → tag `ssh`, source `0.0.0.0/0` |
| `google_compute_firewall` | `flask-app-firewall`: TCP 5000, source `0.0.0.0/0` |
| Output | `Web-server-URL` |

### Track B (`ansible/vpc.tf`)

| Resource | Details |
|----------|---------|
| `google_compute_address` | `example-ip` |
| `google_compute_instance` | `example-instance`, `n1-standard-1`, debian-10, default network |
| `local_file` | `cluster.inventory` |
| Outputs | `instance_ip`, `instance_fip` |

---

## Cost and safety

- Track A (`f1-micro`) is inexpensive; Track B (`n1-standard-1` + reserved IP) costs more if left running. Always `terraform destroy` when finished.
- Firewall rules allow ingress from `0.0.0.0/0`. Restrict sources for anything beyond a short-lived lab.
- Never commit `key.json`, `*.tfstate*`, or `.terraform/`.

---

## Setup gotchas (read before apply)

- Replace every placeholder in `main.tf` / `ansible/vpc.tf` with real project IDs and SSH paths, or `plan`/`apply` will fail.
- Track B expects a service-account key at `ansible/key.json`.
- Track A installs Flask on the VM but does not copy or start `app.py`. After apply, SSH in, deploy `app.py`, and run it before curling `Web-server-URL`.
- Track A does not set `ssh-keys` metadata. Use `gcloud compute ssh flask-vm --zone=us-east4-a` (or configure OS Login / project keys) to reach the instance.
