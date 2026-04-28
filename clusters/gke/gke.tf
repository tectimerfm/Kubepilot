locals {
  gke_image_type = var.node_os == "ubuntu" ? "UBUNTU_CONTAINERD" : "COS_CONTAINERD"
}

locals {
  gcp_label_workspace = lower(replace(terraform.workspace, "/[^a-z0-9_-]/", ""))
}

resource "google_container_cluster" "gke" {
  name     = "gke-${local.name_prefix}"
  location = var.region

  node_locations = ["${var.region}-a"]  # ex.: "us-central1-a"

  # Optional: pin master minimum version
  min_master_version = var.kubernetes_version

  resource_labels = {
    owner     = "support-${local.gcp_label_workspace}"
    workspace = local.gcp_label_workspace
  }

  network    = var.network
  subnetwork = var.subnetwork

  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = false
}

resource "google_container_node_pool" "primary" {
  name     = "primary"
  location = var.region
  cluster  = google_container_cluster.gke.name

  # Optional: pin node pool version (avoid setting if you use auto-upgrade)
  version = var.kubernetes_version

  node_count = var.node_count

  node_locations = ["${var.region}-a"]

  node_config {
    resource_labels = {
      owner     = "support-${local.gcp_label_workspace}"
      workspace = local.gcp_label_workspace
    }
    machine_type = var.machine_type
    image_type   = local.gke_image_type

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  depends_on = [google_container_cluster.gke]
}

output "gke_cluster_name" {
  value = google_container_cluster.gke.name
}

output "gke_cluster_endpoint" {
  value = google_container_cluster.gke.endpoint
}
