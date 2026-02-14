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
