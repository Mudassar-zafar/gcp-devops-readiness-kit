variable "project_id" {
  description = "GCP project to deploy into."
  type        = string
}

variable "region" {
  description = "Primary region."
  type        = string
  default     = "europe-west3"
}

variable "env" {
  description = "Environment name, used in resource naming (e.g. staging, prod)."
  type        = string
  default     = "staging"
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
  default     = "app"
}

variable "node_machine_type" {
  description = "Node pool machine type."
  type        = string
  default     = "e2-standard-4"
}

variable "node_min_count" {
  description = "Autoscaling minimum nodes per zone."
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Autoscaling maximum nodes per zone."
  type        = number
  default     = 3
}

variable "alert_email" {
  description = "Email address for monitoring alerts."
  type        = string
}

variable "master_authorized_cidrs" {
  description = "CIDRs allowed to reach the GKE control plane. The default is open for first-run convenience; tighten to office/VPN ranges before real use."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{
    cidr_block   = "0.0.0.0/0"
    display_name = "OPEN-tighten-before-production"
  }]
}
