# DNS records for the root domain.
# A/AAAA content is managed by the dns-failover Worker at runtime.
# lifecycle ignore_changes prevents OpenTofu from overriding Worker changes.

resource "cloudflare_dns_record" "root_a" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "A"
  content = var.homelab_ipv4
  ttl     = 60
  proxied = false

  lifecycle {
    ignore_changes = [content, comment]
  }
}

resource "cloudflare_dns_record" "root_aaaa" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "AAAA"
  content = var.homelab_ipv6
  ttl     = 60
  proxied = false

  lifecycle {
    ignore_changes = [content, comment]
  }
}

resource "cloudflare_dns_record" "www_cname" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  type    = "CNAME"
  content = var.domain
  ttl     = 60
  proxied = false
}
