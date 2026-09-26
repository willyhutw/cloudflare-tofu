output "worker_name" {
  description = "Deployed Worker script name"
  value       = cloudflare_worker.dns_failover.name
}

output "dns_record_ids" {
  description = "DNS record IDs"
  value = {
    root_a    = cloudflare_dns_record.root_a.id
    root_aaaa = cloudflare_dns_record.root_aaaa.id
    www_cname = cloudflare_dns_record.www_cname.id
  }
}

output "r2_backup_bucket_name" {
  description = "R2 bucket name for homelab backups"
  value       = cloudflare_r2_bucket.homelab_backup.name
}

output "r2_tofu_state_bucket_name" {
  description = "R2 bucket name for OpenTofu remote state"
  value       = cloudflare_r2_bucket.tofu_state.name
}
