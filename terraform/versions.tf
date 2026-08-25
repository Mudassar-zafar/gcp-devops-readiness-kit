terraform {
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Recommended: remote state in a versioned GCS bucket.
  # backend "gcs" {
  #   bucket = "your-tf-state-bucket"
  #   prefix = "gke-starter"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
