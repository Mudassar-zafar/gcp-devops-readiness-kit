resource "google_monitoring_notification_channel" "email" {
  display_name = "${var.env} on-call email"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

# One representative alert: GKE node CPU sustained above 85 percent.
# Real engagements add SLO-based alerting per service on top of this.
resource "google_monitoring_alert_policy" "node_cpu" {
  display_name = "${var.env} · GKE node CPU > 85% (15m)"
  combiner     = "OR"

  conditions {
    display_name = "Node allocatable CPU utilization"

    condition_threshold {
      filter          = "resource.type = \"k8s_node\" AND metric.type = \"kubernetes.io/node/cpu/allocatable_utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.85
      duration        = "900s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  documentation {
    content   = "Sustained node CPU pressure. Check HPA limits and node pool autoscaling ceiling before adding capacity."
    mime_type = "text/markdown"
  }
}
