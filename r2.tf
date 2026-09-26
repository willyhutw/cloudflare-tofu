# R2 bucket for homelab backups (micro cluster etcd snapshots + PKI).
# R2 must be enabled on the account before this bucket can be created.

locals {
  # R2 lifecycle max_age is in seconds, not days.
  one_day_seconds = 24 * 60 * 60
}

resource "cloudflare_r2_bucket" "homelab_backup" {
  account_id = var.cloudflare_account_id
  name       = "willy-homelab-backup"
  location   = "apac"
}

resource "cloudflare_r2_bucket_lifecycle" "homelab_backup" {
  account_id  = var.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.homelab_backup.name

  rules = [{
    id      = "Expire micro/ objects after 7 days"
    enabled = true

    conditions = {
      prefix = "micro/"
    }

    delete_objects_transition = {
      condition = {
        type    = "Age"
        max_age = 7 * local.one_day_seconds
      }
    }

    abort_multipart_uploads_transition = {
      condition = {
        type    = "Age"
        max_age = 1 * local.one_day_seconds
      }
    }
  }]
}
