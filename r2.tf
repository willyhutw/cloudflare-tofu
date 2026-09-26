# R2 buckets:
#   - willyhutw-homelab-backup: off-site homelab backups (micro cluster etcd snapshots + PKI)
#   - willyhutw-tofu-state:     OpenTofu remote state for this repo (S3 backend, see backend.hcl.example)
# R2 must be enabled on the account before these buckets can be created.

locals {
  # R2 lifecycle max_age is in seconds, not days.
  one_day_seconds = 24 * 60 * 60
}

resource "cloudflare_r2_bucket" "homelab_backup" {
  account_id = var.cloudflare_account_id
  name       = "willyhutw-homelab-backup"
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

resource "cloudflare_r2_bucket" "tofu_state" {
  account_id = var.cloudflare_account_id
  name       = "willyhutw-tofu-state"
  location   = "apac"

  # Holds this repo's remote state; never destroy it via OpenTofu.
  lifecycle {
    prevent_destroy = true
  }
}

# State must be kept forever: no delete_objects_transition here.
# Only clean up incomplete multipart uploads.
resource "cloudflare_r2_bucket_lifecycle" "tofu_state" {
  account_id  = var.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.tofu_state.name

  rules = [{
    id      = "Abort incomplete multipart uploads after 1 day"
    enabled = true

    conditions = {
      prefix = ""
    }

    abort_multipart_uploads_transition = {
      condition = {
        type    = "Age"
        max_age = 1 * local.one_day_seconds
      }
    }
  }]
}
