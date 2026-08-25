output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "GKE control plane endpoint."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "artifact_registry" {
  description = "Container image repository path."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.containers.repository_id}"
}

output "node_service_account" {
  description = "Least-privilege node service account."
  value       = google_service_account.gke_nodes.email
}
