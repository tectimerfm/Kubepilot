#!/usr/bin/env bash

echo -e '\033[34m'
echo " █████╗  ██████╗ ██╗   ██╗ █████╗     ██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗ ██╗██╗      ██████╗ ████████╗"
echo "██╔══██╗██╔═══██╗██║   ██║██╔══██╗    ██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔══██╗██║██║     ██╔═══██╗╚══██╔══╝"
echo "███████║██║   ██║██║   ██║███████║    █████╔╝ ██║   ██║██████╔╝█████╗  ██████╔╝██║██║     ██║   ██║   ██║"
echo "██╔══██║██║▄▄ ██║██║   ██║██╔══██║    ██╔═██╗ ██║   ██║██╔══██╗██╔══╝  ██╔═══╝ ██║██║     ██║   ██║   ██║"
echo "██║  ██║╚██████╔╝╚██████╔╝██║  ██║    ██║  ██╗╚██████╔╝██████╔╝███████╗██║     ██║███████╗╚██████╔╝   ██║"
echo "╚═╝  ╚═╝ ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝    ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝     ╚═╝╚══════╝ ╚═════╝    ╚═╝"
echo -e '\033[0;0m'

# texto menor (dim)
echo -e '\033[2mAqua KubePilot automates end-to-end Kubernetes provisioning across cloud providers using Bash + Terraform, and optionally deploys the Aqua Enforcer via Helm for immediate runtime protection.\033[0m'

set -euo pipefail

# tf_k8s_aqua_multicloud.sh (Bash 3.2 compatible)
# - Choose cluster flavour: eks / aks / gke
# - Guide authentication
# - Create/destroy with Terraform workspaces
# - Optionally install Aqua Enforcer via Helm
#
# Persists inputs:   .tf_input_db
# Generates varfile: clusters/<flavour>/.generated.auto.tfvars

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_FILE="$ROOT_DIR/.tf_input_db"

trim() { awk '{$1=$1;print}'; }

ensure_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: required command not found: $c" >&2; exit 1; }
}

ensure_terraform() { ensure_cmd terraform; }

db_init() {
  if [[ ! -f "$DB_FILE" ]]; then
    {
      echo "# Persisted inputs for Terraform runs (do not commit)"
    } > "$DB_FILE"
  fi
}

db_get() {
  # Usage: db_get key [default]
  local key="$1"
  local def="${2:-}"
  local val=""
  if [[ -f "$DB_FILE" ]]; then
    val="$(grep -E "^${key}=" "$DB_FILE" 2>/dev/null | tail -n1 | sed -E "s/^${key}=//" || true)"
  fi
  if [[ -n "$val" ]]; then
    printf "%s" "$val"
  else
    printf "%s" "$def"
  fi
}

db_set() {
  # Usage: db_set key value
  local key="$1"
  local value="$2"

  db_init

  # Escape backslashes and quotes for safe storage
  value="$(printf "%s" "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')"

  if grep -qE "^${key}=" "$DB_FILE"; then
    # macOS sed needs -i '' for in-place
    sed -i '' -E "s#^${key}=.*#${key}=${value}#g" "$DB_FILE"
  else
    echo "${key}=${value}" >> "$DB_FILE"
  fi
}

prompt() {
  # prompt key "Label" "default"
  local key="$1"
  local label="$2"
  local def="${3:-}"
  local value

  if [[ -n "$def" ]]; then
    read -r -p "$label [$def]: " value
    value="$(printf "%s" "${value:-$def}" | trim)"
  else
    read -r -p "$label: " value
    value="$(printf "%s" "$value" | trim)"
  fi

  db_set "$key" "$value"
}

prompt_yesno() {
  # prompt_yesno key "Label" default(true/false)
  local key="$1"
  local label="$2"
  local def="${3:-false}"
  local d="y/N"
  [[ "$def" == "true" ]] && d="Y/n"

  local ans
  read -r -p "$label ($d): " ans
  ans="$(printf "%s" "${ans:-}" | tr '[:upper:]' '[:lower:]' | trim)"

  if [[ -z "$ans" ]]; then
    db_set "$key" "$def"
    return 0
  fi

  case "$ans" in
    y|yes) db_set "$key" "true" ;;
    n|no)  db_set "$key" "false" ;;
    *)     echo "Please answer y or n." >&2; prompt_yesno "$key" "$label" "$def" ;;
  esac
}

prompt_secret() {
  # prompt_secret key "Label" "default"
  local key="$1"
  local label="$2"
  local def="${3:-}"
  local value

  if [[ -n "$def" ]]; then
    read -r -s -p "$label [****]: " value
    echo
    value="$(printf "%s" "${value:-$def}" | trim)"
  else
    read -r -s -p "$label: " value
    echo
    value="$(printf "%s" "$value" | trim)"
  fi

  db_set "$key" "$value"
}

extract_node_os_options() {
  # Extract options from: contains(["a","b"], var.node_os)
  local vars_file="$1"
  if [[ ! -f "$vars_file" ]]; then
    echo ""
    return 0
  fi

  local line
  line="$(grep -E 'contains\(\[[^]]+\], *var\.node_os\)' -n "$vars_file" | head -n1 || true)"
  if [[ -z "$line" ]]; then
    echo ""
    return 0
  fi

  local list
  list="$(echo "$line" | sed -E 's/.*contains\(\[([^]]+)\].*/\1/')"
  echo "$list" | tr -d '"' | tr -d "'" | tr ',' ' ' | awk '{$1=$1;print}'
}

tf() {
  # terraform wrapper: terraform -chdir=<dir> ...
  terraform -chdir="$TF_DIR" "$@"
}

tf_init() { tf init -upgrade; }

tf_workspace_select_or_create() {
  local ws="$1"
  if tf workspace list | sed 's/*//g' | awk '{print $1}' | grep -qx "$ws"; then
    tf workspace select "$ws" >/dev/null
  else
    tf workspace new "$ws" >/dev/null
    tf workspace select "$ws" >/dev/null
  fi
}

warn_if_missing_eks_tfvars() {
  # EKS requires vpc/subnets/sg ids; typically provided via terraform.tfvars
  if [[ "$FLAVOUR" == "eks" ]]; then
    local tfvars="$TF_DIR/terraform.tfvars"

    if [[ ! -f "$tfvars" ]]; then
      echo
      echo "WARNING: clusters/eks/terraform.tfvars not found."
      echo "EKS requires: vpc_id, subnet_ids, security_group_ids."
      echo

      # Special optional convenience for a very specific internal AWS environment.
      echo "OPTIONAL convenience:"
      echo "  I can create clusters/eks/terraform.tfvars for you with pre-defined networking values."
      echo
      echo "             vpc_id             = "vpc-00e3afef8b5f4ad67""
      echo "             subnet_ids         = ["subnet-046ad0cd38c7e05cb", "subnet-070627f825b1ca7a5"]"
      echo "             security_group_ids = ["sg-0390a728fe71d50ca"]"
      echo
      echo "  IMPORTANT: These values are ONLY valid for the AWS environment named: aws-aqua-cross-dep-cs"
      echo "             and for the default region: us-west-1"
      echo
      echo "             (If you are NOT using that environment/region, choose 'no' and provide your own values.)"
      echo

      prompt_yesno eks_autocreate_tfvars "Auto-create clusters/eks/terraform.tfvars with aws-aqua-cross-dep-cs (us-west-1) defaults?" "false"
      local doit; doit="$(db_get eks_autocreate_tfvars "false")"

      if [[ "$doit" == "true" ]]; then
        cat > "$tfvars" <<'EOF'
# Auto-created by tf_k8s_aqua_multicloud.sh
# WARNING: These values are ONLY valid for the AWS environment "aws-aqua-cross-dep-cs"
#          and for the default region "us-west-1".
# If you are not using that environment/region, replace these values.

vpc_id             = "vpc-00e3afef8b5f4ad67"
subnet_ids         = ["subnet-046ad0cd38c7e05cb", "subnet-070627f825b1ca7a5"]
security_group_ids = ["sg-0390a728fe71d50ca"]
EOF
        echo
        echo "Created: $tfvars"
        echo
      else
        echo
        echo "Proceeding without terraform.tfvars."
        echo "You must provide vpc_id/subnet_ids/security_group_ids (or equivalent defaults in Terraform) before apply."
        echo
      fi

      return 0
    fi

    # If file exists, but the keys are missing, suggest (optional) update.
    local missing="false"
    grep -qE '^\s*vpc_id\s*=' "$tfvars" || missing="true"
    grep -qE '^\s*subnet_ids\s*=' "$tfvars" || missing="true"
    grep -qE '^\s*security_group_ids\s*=' "$tfvars" || missing="true"

    if [[ "$missing" == "true" ]]; then
      echo
      echo "WARNING: clusters/eks/terraform.tfvars exists but is missing one or more of:"
      echo "  - vpc_id"
      echo "  - subnet_ids"
      echo "  - security_group_ids"
      echo
      echo "If you are using the AWS environment 'aws-aqua-cross-dep-cs' in region us-west-1,"
      echo "you can add the known values below to the file manually (or choose to let Terraform fail and fix later):"
      echo
      echo "  vpc_id             = \"vpc-00e3afef8b5f4ad67\""
      echo "  subnet_ids         = [\"subnet-046ad0cd38c7e05cb\", \"subnet-070627f825b1ca7a5\"]"
      echo "  security_group_ids = [\"sg-0390a728fe71d50ca\"]"
      echo
    fi
  fi
}

auth_guide() {
  case "$FLAVOUR" in
    eks)
      ensure_cmd aws
      echo
      echo "AWS authentication guide (EKS):"
      echo "  1) If using SSO: aws sso login --profile <profile>"
      echo "  2) Verify: aws sts get-caller-identity [--profile <profile>]"
      echo
      ;;
    aks)
      ensure_cmd az
      echo
      echo "Azure authentication guide (AKS):"
      echo "  1) In another tab/terminal, run the command shown below. This will open a browser window for you to authenticate with Azure."
      echo "  2) az login"
      echo "  3) az account show"
      echo "  4) (optional) az account set --subscription <SUBSCRIPTION_ID>"
      echo
      ;;
    gke)
      ensure_cmd gcloud
      echo
      echo "Mandatory GCP authentication is not handled by this script. Please run the following commands in another tab/terminal to authenticate with GCP before proceeding."
      echo
      echo "GCP authentication guide (GKE):"
      echo "  1) gcloud auth login"
      echo "  2) gcloud auth application-default login"
      echo "  3) gcloud config set project <PROJECT_ID>"
      echo "     e.g.: gcloud config set project aqua-csm-support-project"
      echo "  4) (optional) gcloud config set compute/region <REGION>"
      echo "     e.g.: gcloud config set compute/region us-central1"
      echo
      ;;
  esac
}

write_tfvars() {
  : > "$TFVARS_FILE"
  echo "# Auto-generated - DO NOT COMMIT" >> "$TFVARS_FILE"

  # Common
  local node_os; node_os="$(db_get "${PFX}node_os" "")"
  local install; install="$(db_get "${PFX}install_aqua_enforcer" "false")"

  [[ -n "$node_os" ]] && echo "node_os = \"${node_os}\"" >> "$TFVARS_FILE"
  echo "install_aqua_enforcer = ${install}" >> "$TFVARS_FILE"

  # Provider-specific vars
  if [[ "$FLAVOUR" == "eks" ]]; then
    local aws_region; aws_region="$(db_get "${PFX}aws_region" "")"
    local aws_profile; aws_profile="$(db_get "${PFX}aws_profile" "")"
    [[ -n "$aws_region" ]]  && echo "aws_region  = \"${aws_region}\"" >> "$TFVARS_FILE"
    [[ -n "$aws_profile" ]] && echo "aws_profile = \"${aws_profile}\"" >> "$TFVARS_FILE"
    local kv; kv="$(db_get "${PFX}kubernetes_version" "")"
    local cv; cv="$(db_get "${PFX}containerd_version" "")"
    local rv; rv="$(db_get "${PFX}eks_ami_release_version" "")"
    [[ -n "$kv" ]] && echo "kubernetes_version = \"${kv}\"" >> "$TFVARS_FILE"
    [[ -n "$cv" ]] && echo "containerd_version = \"${cv}\"" >> "$TFVARS_FILE"
    [[ -n "$rv" ]] && echo "eks_ami_release_version = \"${rv}\"" >> "$TFVARS_FILE"
  fi

  if [[ "$FLAVOUR" == "aks" ]]; then
    local loc; loc="$(db_get "${PFX}azure_location" "")"
    local sub; sub="$(db_get "${PFX}azure_subscription_id" "")"
    [[ -n "$loc" ]] && echo "azure_location = \"${loc}\"" >> "$TFVARS_FILE"
    [[ -n "$sub" ]] && echo "azure_subscription_id = \"${sub}\"" >> "$TFVARS_FILE"

    local kv; kv="$(db_get "${PFX}kubernetes_version" "")"
    local cv; cv="$(db_get "${PFX}containerd_version" "")"
    [[ -n "$kv" ]] && echo "kubernetes_version = \"${kv}\"" >> "$TFVARS_FILE"
    [[ -n "$cv" ]] && echo "containerd_version = \"${cv}\"" >> "$TFVARS_FILE"
  fi

  if [[ "$FLAVOUR" == "gke" ]]; then
    local pid; pid="$(db_get "${PFX}project_id" "")"
    local reg; reg="$(db_get "${PFX}region" "")"
    [[ -n "$pid" ]] && echo "project_id = \"${pid}\"" >> "$TFVARS_FILE"
    [[ -n "$reg" ]] && echo "region     = \"${reg}\"" >> "$TFVARS_FILE"

    local kv; kv="$(db_get "${PFX}kubernetes_version" "")"
    local cv; cv="$(db_get "${PFX}containerd_version" "")"
    [[ -n "$kv" ]] && echo "kubernetes_version = \"${kv}\"" >> "$TFVARS_FILE"
    [[ -n "$cv" ]] && echo "containerd_version = \"${cv}\"" >> "$TFVARS_FILE"
  fi

  # Aqua Enforcer
  if [[ "$install" == "true" ]]; then
    local aqua_platform; aqua_platform="$(db_get "${PFX}aqua_platform" "")"
    local aqua_tag; aqua_tag="$(db_get "${PFX}aqua_enforcer_image_tag" "")"
    local gateway_address; gateway_address="$(db_get "${PFX}gateway_address" "")"
    local gateway_port; gateway_port="$(db_get "${PFX}gateway_port" "")"
    local user; user="$(db_get "${PFX}aqua_registry_username" "")"
    local pass; pass="$(db_get "${PFX}aqua_registry_password" "")"
    local token; token="$(db_get "${PFX}aqua_enforcer_token" "")"

    [[ -n "$aqua_platform" ]] && echo "aqua_platform = \"${aqua_platform}\"" >> "$TFVARS_FILE"
    [[ -n "$aqua_tag" ]]      && echo "aqua_enforcer_image_tag = \"${aqua_tag}\"" >> "$TFVARS_FILE"
    [[ -n "$gateway_address" ]] && echo "gateway_address = \"${gateway_address}\"" >> "$TFVARS_FILE"
    [[ -n "$gateway_port" ]] && echo "gateway_port = ${gateway_port}" >> "$TFVARS_FILE"

    [[ -n "$user"  ]] && echo "aqua_registry_username = \"${user}\"" >> "$TFVARS_FILE"
    [[ -n "$pass"  ]] && echo "aqua_registry_password = \"${pass}\"" >> "$TFVARS_FILE"
    [[ -n "$token" ]] && echo "aqua_enforcer_token    = \"${token}\"" >> "$TFVARS_FILE"
  fi
}

load_tfvars_into_db() {
  # Load key/values from a .generated.auto.tfvars into the DB for the given prefix.
  # Supports lines like: key = "value", key = 123, key = true
  local file="$1"
  local pfx="$2"

  [[ -f "$file" ]] || return 0

  while IFS= read -r line; do
    line="$(printf "%s" "$line" | sed -E 's/#.*$//g' | trim)"
    [[ -z "$line" ]] && continue

    if echo "$line" | grep -qE '^[A-Za-z0-9_]+\s*='; then
      local key val
      key="$(printf "%s" "$line" | sed -E 's/^([A-Za-z0-9_]+)\s*=.*$/\1/')"
      val="$(printf "%s" "$line" | sed -E 's/^[A-Za-z0-9_]+\s*=\s*//')"
      val="$(printf "%s" "$val" | sed -E 's/^"(.*)"$/\1/')"
      db_set "${pfx}${key}" "$val"
    fi
  done < "$file"
}

setup_aks_kubeconfig() {
  # After AKS create, build ~/.kube/config to interact with the cluster
  ensure_cmd az

  local rg name
  rg="$(tf output -raw aks_resource_group 2>/dev/null || true)"
  name="$(tf output -raw aks_cluster_name 2>/dev/null || true)"

  if [[ -z "$rg" || -z "$name" ]]; then
    echo "WARNING: Could not read AKS outputs (aks_resource_group / aks_cluster_name). Skipping kubeconfig setup."
    return 0
  fi

  echo
  echo "Configuring kubeconfig for AKS cluster..."
  echo "  Resource group: $rg"
  echo "  Cluster name:   $name"
  echo

  mkdir -p "$HOME/.kube"
  az aks get-credentials --resource-group "$rg" --name "$name" --overwrite-existing
  echo "Kubeconfig updated at: $HOME/.kube/config"
}

setup_eks_kubeconfig() {
  # After EKS create, build/merge ~/.kube/config to interact with the cluster
  ensure_cmd aws

  local name region profile
  name="$(tf output -raw eks_cluster_name 2>/dev/null || true)"
  region="$(db_get "${PFX}aws_region" "us-west-1")"
  profile="$(db_get "${PFX}aws_profile" "")"

  if [[ -z "$name" ]]; then
    echo "WARNING: Could not read EKS output eks_cluster_name. Skipping kubeconfig setup."
    return 0
  fi

  echo
  echo "Configuring kubeconfig for EKS cluster..."
  echo "  Cluster name: $name"
  echo "  Region:       $region"
  [[ -n "$profile" ]] && echo "  Profile:      $profile"
  echo

  mkdir -p "$HOME/.kube"

  if [[ -n "$profile" ]]; then
    aws eks update-kubeconfig --name "$name" --region "$region" --profile "$profile"
  else
    aws eks update-kubeconfig --name "$name" --region "$region"
  fi

  echo "Kubeconfig updated at: $HOME/.kube/config"
}

setup_gke_kubeconfig() {
  # After GKE create, build/merge ~/.kube/config to interact with the cluster
  ensure_cmd gcloud

  local name region project
  name="$(tf output -raw gke_cluster_name 2>/dev/null || true)"
  region="$(db_get "${PFX}region" "us-central1")"
  project="$(db_get "${PFX}project_id" "")"

  if [[ -z "$name" ]]; then
    echo "WARNING: Could not read GKE output gke_cluster_name. Skipping kubeconfig setup."
    return 0
  fi

  if [[ -z "$project" ]]; then
    echo "WARNING: project_id is empty. Skipping kubeconfig setup."
    return 0
  fi

  echo
  echo "Configuring kubeconfig for GKE cluster..."
  echo "  Cluster name: $name"
  echo "  Region:       $region"
  echo "  Project:      $project"
  echo

  mkdir -p "$HOME/.kube"
  gcloud container clusters get-credentials "$name" --region "$region" --project "$project"

  echo "Kubeconfig updated at: $HOME/.kube/config"
}

prompt_flavour() {
  local def; def="$(db_get last_flavour "eks")"
  read -r -p "Which cluster flavour do you want to manage? (eks/aks/gke) [$def]: " FLAVOUR
  FLAVOUR="$(printf "%s" "${FLAVOUR:-$def}" | tr '[:upper:]' '[:lower:]' | trim)"
  case "$FLAVOUR" in
    eks|aks|gke) ;;
    *) echo "Invalid flavour. Choose eks, aks, or gke." >&2; exit 1 ;;
  esac
  db_set last_flavour "$FLAVOUR"
}

prompt_action_global() {
  local def; def="$(db_get last_action_global "create")"
  read -r -p "Do you want to (c)reate or (d)estroy the cluster? [$def]: " action
  action="$(printf "%s" "${action:-$def}" | tr '[:upper:]' '[:lower:]' | trim)"
  case "$action" in
    c|create) ACTION="create" ;;
    d|destroy) ACTION="destroy" ;;
    *) echo "Invalid choice. Use create or destroy." >&2; exit 1 ;;
  esac
  db_set last_action_global "$ACTION"
}

prompt_flavour_destroy() {
  local def; def="$(db_get last_flavour "eks")"
  read -r -p "Which cluster flavour do you want to destroy? (eks/aks/gke) [$def]: " FLAVOUR
  FLAVOUR="$(printf "%s" "${FLAVOUR:-$def}" | tr '[:upper:]' '[:lower:]' | trim)"
  case "$FLAVOUR" in
    eks|aks|gke) ;;
    *) echo "Invalid flavour. Choose eks, aks, or gke." >&2; exit 1 ;;
  esac
  db_set last_flavour "$FLAVOUR"
}

prompt_action() {
  local def; def="$(db_get "${PFX}last_action" "create")"
  read -r -p "Do you want to (c)reate or (d)estroy the cluster? [$def]: " action
  action="$(printf "%s" "${action:-$def}" | tr '[:upper:]' '[:lower:]' | trim)"
  case "$action" in
    c|create) ACTION="create" ;;
    d|destroy) ACTION="destroy" ;;
    *) echo "Invalid choice. Use create or destroy." >&2; exit 1 ;;
  esac
  db_set "${PFX}last_action" "$ACTION"
}

prompt_provider_inputs() {
  case "$FLAVOUR" in
    eks)
      # Optional overrides; defaults are defined in clusters/eks/variables.tf
      local rdef; rdef="$(db_get "${PFX}aws_region" "us-west-1")"
      prompt "${PFX}aws_region"  "AWS region (EKS)" "$rdef"

      local pdef; pdef="$(db_get "${PFX}aws_profile" "")"
      prompt "${PFX}aws_profile" "AWS profile (optional; example: aws-aqua-cross-dep-cs-633291361733)" "$pdef"

      # Optional version pins / tracking (leave empty to use defaults)
      local kvdef; kvdef="$(db_get "${PFX}kubernetes_version" "")"
      prompt "${PFX}kubernetes_version" "EKS Kubernetes version (optional; leave empty to use default; example: 1.33 - for more information, see https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)" "$kvdef"

      local cvdef; cvdef="$(db_get "${PFX}containerd_version" "")"
      prompt "${PFX}containerd_version" "EKS containerd version (optional; tracking only; AMI controls this)" "$cvdef"
      ;;
    aks)
      local ldef; ldef="$(db_get "${PFX}azure_location" "eastus")"
      prompt "${PFX}azure_location" "Enter the Azure location (uksouth, eastus, etc.)" "$ldef"

      local sdef; sdef="$(db_get "${PFX}azure_subscription_id" "")"
      prompt "${PFX}azure_subscription_id" "Azure subscription ID (For the Azure Aqua Customer Success subscription, the default value should be 71d0a3d0-ad98-4db0-b732-f95dc566a10a)" "$sdef"

      # Optional AKS version pins (leave empty to use Azure defaults)
      local kvdef; kvdef="$(db_get "${PFX}kubernetes_version" "")"
      prompt "${PFX}kubernetes_version" "AKS Kubernetes version (optional; example: 1.29.7 - for more information, see https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions)" "$kvdef"

      local cvdef; cvdef="$(db_get "${PFX}containerd_version" "")"
      prompt "${PFX}containerd_version" "AKS containerd version (optional; example: 1.7.24 - for more information, see https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions)" "$cvdef"
      ;;
    gke)
      local pdef; pdef="$(db_get "${PFX}project_id" "")"
      prompt "${PFX}project_id" "GCP project_id (GKE)" "$pdef"

      local rdef; rdef="$(db_get "${PFX}region" "us-central1")"
      prompt "${PFX}region" "GCP region (GKE)" "$rdef"

      # Optional version pins / tracking (leave empty to use defaults)
      local kvdef; kvdef="$(db_get "${PFX}kubernetes_version" "")"
      prompt "${PFX}kubernetes_version" "GKE Kubernetes version (optional; leave empty to use default; example: 1.29.7-gke.100 - for more information, see https://cloud.google.com/kubernetes-engine/docs/release-notes)" "$kvdef"

      local cvdef; cvdef="$(db_get "${PFX}containerd_version" "")"
      prompt "${PFX}containerd_version" "GKE containerd version (optional; tracking only; node image controls this - for more information, see https://cloud.google.com/kubernetes-engine/docs/release-notes)" "$cvdef"
      ;;
  esac
}

# Requested improvement:
# - Auto-fill aqua_platform based on selected cluster flavour (eks/gke/aks)
# - Prompt example must include ONLY: eks, gke, aks
prompt_aqua_platform() {
  local auto="$FLAVOUR"

  # Automatically fill and display the auto-selected platform.
  echo
  echo "Aqua platform auto-selected from cluster flavour: $auto"
  echo

  # Default to auto; allow override but validate to only eks/aks/gke
  while true; do
    prompt "${PFX}aqua_platform" "Select the aqua_platform flavor for the Enforcer to be implemented (example: eks, gke, aks)" "$auto"
    local v; v="$(db_get "${PFX}aqua_platform" "$auto")"
    case "$v" in
      eks|aks|gke) break ;;
      *) echo "Invalid aqua_platform. Allowed values: eks, aks, gke." >&2 ;;
    esac
  done
}

main() {
  ensure_terraform
  db_init

  # 1) First question: create or destroy
  prompt_action_global

  if [[ "$ACTION" == "destroy" ]]; then
    # For destroy: use last known flavour and load provider/helm inputs from last generated tfvars
    FLAVOUR="$(db_get last_flavour "eks")"
    TF_DIR="$ROOT_DIR/clusters/$FLAVOUR"
    if [[ ! -d "$TF_DIR" ]]; then
      echo "ERROR: Terraform directory not found: $TF_DIR" >&2
      exit 1
    fi

    TFVARS_FILE="$TF_DIR/.generated.auto.tfvars"
    PFX="${FLAVOUR}_"

    # Load values from previous run so we can skip flavour/auth/provider prompts
    load_tfvars_into_db "$TFVARS_FILE" "$PFX"

    # Init terraform for the selected flavour
    tf_init
    warn_if_missing_eks_tfvars

    # Jump directly to workspace prompt
    local ws_def; ws_def="$(db_get "${PFX}last_workspace" "")"
    prompt "${PFX}workspace" "Workspace name to destroy" "$ws_def"
    local ws; ws="$(db_get "${PFX}workspace" "")"
    db_set "${PFX}last_workspace" "$ws"

    tf_workspace_select_or_create "$ws"
    echo "Using workspace: $(tf workspace show)"

    # Ensure basics exist for varfile (node_os and install flags should be present from tfvars, otherwise ask)
    local node_os; node_os="$(db_get "${PFX}node_os" "")"
    if [[ -z "$node_os" ]]; then
      local opts; opts="$(extract_node_os_options "$TF_DIR/variables.tf")"
      if [[ -n "$opts" ]]; then
        echo "Node OS options found: $opts"
        prompt "${PFX}node_os" "Choose node_os (e.g., $opts)" "$(echo "$opts" | awk '{print $1}')"
      else
        prompt "${PFX}node_os" "Choose node_os (see clusters/$FLAVOUR/variables.tf)" "default"
      fi
    fi

    local install; install="$(db_get "${PFX}install_aqua_enforcer" "")"
    if [[ -z "$install" ]]; then
      prompt_yesno "${PFX}install_aqua_enforcer" "Was Aqua Enforcer installed in this workspace?" "false"
      install="$(db_get "${PFX}install_aqua_enforcer" "false")"
    fi

    if [[ "$install" == "true" ]]; then
      local ap; ap="$(db_get "${PFX}aqua_platform" "")"
      [[ -z "$ap" ]] && db_set "${PFX}aqua_platform" "$FLAVOUR"

      local atag; atag="$(db_get "${PFX}aqua_enforcer_image_tag" "")"
      [[ -z "$atag" ]] && prompt "${PFX}aqua_enforcer_image_tag" "image.tag (Enforcer version; example: 2022.4.860.26)" "2022.4.860.26"

      local ga; ga="$(db_get "${PFX}gateway_address" "")"
      [[ -z "$ga" ]] && prompt "${PFX}gateway_address" "gateway_address (example: c1fae5dbe2-gw.cloud.aquasec.com)" "c1fae5dbe2-gw.cloud.aquasec.com"

      local gp; gp="$(db_get "${PFX}gateway_port" "")"
      [[ -z "$gp" ]] && prompt "${PFX}gateway_port" "gateway_port (example: 443)" "443"

      local au; au="$(db_get "${PFX}aqua_registry_username" "")"
      [[ -z "$au" ]] && prompt "${PFX}aqua_registry_username" "aqua_registry_username" ""

      local apw; apw="$(db_get "${PFX}aqua_registry_password" "")"
      [[ -z "$apw" ]] && prompt_secret "${PFX}aqua_registry_password" "aqua_registry_password"

      local tok; tok="$(db_get "${PFX}aqua_enforcer_token" "")"
      [[ -z "$tok" ]] && prompt_secret "${PFX}aqua_enforcer_token" "aqua_enforcer_token"
    fi

    write_tfvars

    echo
    echo "Running: terraform destroy -chdir=$TF_DIR -var-file=.generated.auto.tfvars"
    tf destroy -var-file=".generated.auto.tfvars"

    prompt_yesno "${PFX}delete_workspace" "Delete the Terraform workspace '$ws' after destroy?" "false"
    local del; del="$(db_get "${PFX}delete_workspace" "false")"
    if [[ "$del" == "true" ]]; then
      tf workspace select default >/dev/null || true
      tf workspace delete "$ws" || true
      echo "Workspace '$ws' deleted (if it existed and was not default)."
    fi

    echo
    echo "Done."
    echo "Saved inputs in: $DB_FILE"
    echo "Generated tfvars: $TFVARS_FILE"
    echo "NOTE: Keep DB/tfvars out of git (may contain secrets)."
    return 0
  fi

  # CREATE path
  prompt_flavour

  TF_DIR="$ROOT_DIR/clusters/$FLAVOUR"
  if [[ ! -d "$TF_DIR" ]]; then
    echo "ERROR: Terraform directory not found: $TF_DIR" >&2
    exit 1
  fi

  TFVARS_FILE="$TF_DIR/.generated.auto.tfvars"
  PFX="${FLAVOUR}_"

  echo
  echo "Selected flavour: $FLAVOUR"
  echo "Terraform directory: $TF_DIR"
  echo

  auth_guide
  prompt_provider_inputs

  # Init terraform for the selected flavour
  tf_init

  warn_if_missing_eks_tfvars

  if [[ "$ACTION" == "create" ]]; then
    local ws_def; ws_def="$(db_get "${PFX}last_workspace" "")"
    prompt "${PFX}workspace" "Workspace name to create/use (ticket id recommended, e.g. FD-12345)" "$ws_def"
    local ws; ws="$(db_get "${PFX}workspace" "")"
    db_set "${PFX}last_workspace" "$ws"

    tf_workspace_select_or_create "$ws"
    echo "Using workspace: $(tf workspace show)"

    # Node OS family (extract from variables.tf if possible)
    local opts; opts="$(extract_node_os_options "$TF_DIR/variables.tf")"
    local node_def; node_def="$(db_get "${PFX}node_os" "")"
    if [[ -n "$opts" ]]; then
      echo "Node OS options found: $opts"
      [[ -z "$node_def" ]] && node_def="$(echo "$opts" | awk '{print $1}')"
      prompt "${PFX}node_os" "Choose node_os (e.g., $opts)" "$node_def"
    else
      # fallback
      [[ -z "$node_def" ]] && node_def="default"
      prompt "${PFX}node_os" "Choose node_os (see clusters/$FLAVOUR/variables.tf)" "$node_def"
    fi

    # Optional (EKS only): pin EKS optimized AMI release_version for managed node groups
    if [[ "$FLAVOUR" == "eks" ]]; then
      echo
      echo "Optional: EKS managed node group AMI pinning"
      echo "  - node_os controls the AMI family (AL2 / AL2023 / Bottlerocket)"
      echo "  - eks_ami_release_version pins the EKS optimized AMI release_version (leave empty for latest)"
      echo "Docs:"
      echo "  https://docs.aws.amazon.com/eks/latest/userguide/retrieve-ami-id.html"
      echo "  https://docs.aws.amazon.com/eks/latest/userguide/retrieve-ami-id-bottlerocket.html"
      echo "  https://docs.aws.amazon.com/systems-manager/latest/userguide/parameter-store-public-parameters-eks.html"
      local rv_def; rv_def="$(db_get "${PFX}eks_ami_release_version" "")"
      prompt "${PFX}eks_ami_release_version" "EKS AMI release_version (optional; example: v1.52.0; leave empty for latest)" "$rv_def"
    fi

    local idef; idef="$(db_get "${PFX}install_aqua_enforcer" "false")"
    prompt_yesno "${PFX}install_aqua_enforcer" "Install Aqua Enforcer (Helm)?" "$idef"

    local install; install="$(db_get "${PFX}install_aqua_enforcer" "false")"
    if [[ "$install" == "true" ]]; then
      # Auto-fill aqua_platform from flavour (requested)
      prompt_aqua_platform

      # Enforcer image tag
      local tag_def; tag_def="$(db_get "${PFX}aqua_enforcer_image_tag" "2022.4.860.26")"
      prompt "${PFX}aqua_enforcer_image_tag" "image.tag (Enforcer version; example: 2022.4.860.26)" "$tag_def"

      # Gateway
      local gw_def; gw_def="$(db_get "${PFX}gateway_address" "c1fae5dbe2-gw.cloud.aquasec.com")"
      prompt "${PFX}gateway_address" "gateway_address (example: c1fae5dbe2-gw.cloud.aquasec.com)" "$gw_def"

      local gp_def; gp_def="$(db_get "${PFX}gateway_port" "443")"
      prompt "${PFX}gateway_port" "gateway_port (example: 443)" "$gp_def"

      # Registry creds + token
      local u_def; u_def="$(db_get "${PFX}aqua_registry_username" "")"
      prompt "${PFX}aqua_registry_username" "aqua_registry_username" "$u_def"

      local p_def; p_def="$(db_get "${PFX}aqua_registry_password" "")"
      prompt_secret "${PFX}aqua_registry_password" "aqua_registry_password" "$p_def"

      local t_def; t_def="$(db_get "${PFX}aqua_enforcer_token" "")"
      prompt_secret "${PFX}aqua_enforcer_token" "aqua_enforcer_token" "$t_def"
    fi

    write_tfvars

    echo
    echo "Running: terraform apply -chdir=$TF_DIR -var-file=.generated.auto.tfvars"
    tf apply -var-file=".generated.auto.tfvars"

    # Configure kubeconfig for interaction with the created cluster
    case "$FLAVOUR" in
      aks) setup_aks_kubeconfig ;;
      eks) setup_eks_kubeconfig ;;
      gke) setup_gke_kubeconfig ;;
    esac

  else
    # DESTROY (this branch is kept for completeness; global destroy short-circuits earlier)
    local ws_def; ws_def="$(db_get "${PFX}last_workspace" "")"
    prompt "${PFX}workspace" "Workspace name to destroy" "$ws_def"
    local ws; ws="$(db_get "${PFX}workspace" "")"
    db_set "${PFX}last_workspace" "$ws"

    tf_workspace_select_or_create "$ws"
    echo "Using workspace: $(tf workspace show)"

    # Ensure basics exist for varfile
    local node_os; node_os="$(db_get "${PFX}node_os" "")"
    if [[ -z "$node_os" ]]; then
      local opts; opts="$(extract_node_os_options "$TF_DIR/variables.tf")"
      if [[ -n "$opts" ]]; then
        echo "Node OS options found: $opts"
        prompt "${PFX}node_os" "Choose node_os (e.g., $opts)" "$(echo "$opts" | awk '{print $1}')"
      else
        prompt "${PFX}node_os" "Choose node_os (see clusters/$FLAVOUR/variables.tf)" "default"
      fi
    fi

    local install; install="$(db_get "${PFX}install_aqua_enforcer" "")"
    if [[ -z "$install" ]]; then
      prompt_yesno "${PFX}install_aqua_enforcer" "Was Aqua Enforcer installed in this workspace?" "false"
      install="$(db_get "${PFX}install_aqua_enforcer" "false")"
    fi

    if [[ "$install" == "true" ]]; then
      # Ensure aqua vars exist
      local ap; ap="$(db_get "${PFX}aqua_platform" "")"
      [[ -z "$ap" ]] && db_set "${PFX}aqua_platform" "$FLAVOUR"

      local atag; atag="$(db_get "${PFX}aqua_enforcer_image_tag" "")"
      [[ -z "$atag" ]] && prompt "${PFX}aqua_enforcer_image_tag" "image.tag (Enforcer version; example: 2022.4.860.26)" "2022.4.860.26"

      local ga; ga="$(db_get "${PFX}gateway_address" "")"
      [[ -z "$ga" ]] && prompt "${PFX}gateway_address" "gateway_address (example: c1fae5dbe2-gw.cloud.aquasec.com)" "c1fae5dbe2-gw.cloud.aquasec.com"

      local gp; gp="$(db_get "${PFX}gateway_port" "")"
      [[ -z "$gp" ]] && prompt "${PFX}gateway_port" "gateway_port (example: 443)" "443"

      local au; au="$(db_get "${PFX}aqua_registry_username" "")"
      [[ -z "$au" ]] && prompt "${PFX}aqua_registry_username" "aqua_registry_username" ""

      local apw; apw="$(db_get "${PFX}aqua_registry_password" "")"
      [[ -z "$apw" ]] && prompt_secret "${PFX}aqua_registry_password" "aqua_registry_password"

      local tok; tok="$(db_get "${PFX}aqua_enforcer_token" "")"
      [[ -z "$tok" ]] && prompt_secret "${PFX}aqua_enforcer_token" "aqua_enforcer_token"
    fi

    write_tfvars

    echo
    echo "Running: terraform destroy -chdir=$TF_DIR -var-file=.generated.auto.tfvars"
    tf destroy -var-file=".generated.auto.tfvars"

    prompt_yesno "${PFX}delete_workspace" "Delete the Terraform workspace '$ws' after destroy?" "false"
    local del; del="$(db_get "${PFX}delete_workspace" "false")"
    if [[ "$del" == "true" ]]; then
      tf workspace select default >/dev/null || true
      tf workspace delete "$ws" || true
      echo "Workspace '$ws' deleted (if it existed and was not default)."
    fi
  fi

  echo
  echo "Done."
  echo "Saved inputs in: $DB_FILE"
  echo "Generated tfvars: $TFVARS_FILE"
  echo "NOTE: Keep DB/tfvars out of git (may contain secrets)."
}

main "$@"
