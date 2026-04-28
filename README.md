# Multi-Cloud Kubernetes (EKS / AKS / GKE) + Optional Aqua Enforcer (Helm)

This repository provides a **single interactive script** to create/destroy Kubernetes clusters on:

- **AWS EKS**
- **Azure AKS**
- **Google GKE**

and optionally install **Aqua Enforcer** using the Aqua Helm chart (`enforcer`).

## Quick Start

```bash
chmod +x tf_k8s_aqua_multicloud.sh
./tf_k8s_aqua_multicloud.sh
```

The script will:
1. Ask whether you want to **create** or **destroy**
2. If **create**, ask which **cluster flavour** you want: `eks`, `aks`, or `gke`
   (If **destroy**, it uses the last flavour you used and loads values from the last generated tfvars)
3. Guide the authentication for the chosen cloud (AWS/Azure/GCP)
4. Create/select a **Terraform workspace**
5. Ask for **node OS family** (options are read from the selected flavour's `variables.tf`)
6. Optionally install **Aqua Enforcer** via Helm

## Local “DB” files

The script persists your last-used values in:

- `.tf_input_db` (key=value DB; do not commit)
- `clusters/<flavour>/.generated.auto.tfvars` (generated var-file; do not commit)

Add them to `.gitignore` (already included).

## Flavour directories

Terraform code is separated per cloud:

- `clusters/eks`
- `clusters/aks`
- `clusters/gke`

Each flavour can also have its own `terraform.tfvars` (local only), e.g. for EKS networking IDs.

See `terraform.tfvars.example` inside each flavour directory.

## Notes

- This is designed for **ticket-based reproduction environments**. Destroy resources when finished.
- Secrets (registry password/token) may be written locally to `.generated.auto.tfvars`. Keep these files out of git.


## AKS extra prompts

When flavour is **aks**, the script can optionally prompt for:
- `kubernetes_version` (optional)
- `containerd_version` (optional; stored for tracking/repro; AKS manages containerd via node images)


## Kubeconfig (automatic)

After a successful **create**, the script will automatically configure `~/.kube/config` so you can run `kubectl` against the new cluster:

- **EKS**: `aws eks update-kubeconfig`
- **AKS**: `az aks get-credentials`
- **GKE**: `gcloud container clusters get-credentials`

> Make sure the corresponding CLI tool is installed and you are authenticated.
