resource "google_artifact_registry_repository" "containers" {
  repository_id = "${var.env}-containers"
  location      = var.region
  format        = "DOCKER"
  description   = "Container images for ${var.env}"

  # Keep storage costs flat: retain recent images, prune the rest.
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 20
    }
  }

  cleanup_policies {
    id     = "delete-stale"
    action = "DELETE"
    condition {
      older_than = "2592000s" # 30 days
    }
  }
}
