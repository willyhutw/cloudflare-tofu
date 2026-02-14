resource "cloudflare_worker" "dns_failover" {
  account_id = var.cloudflare_account_id
  name       = "dns-failover"
}

resource "cloudflare_worker_version" "dns_failover" {
  account_id         = var.cloudflare_account_id
  worker_id          = cloudflare_worker.dns_failover.id
  compatibility_date = "2024-01-01"
  main_module        = "worker.js"

  modules = [{
    name         = "worker.js"
    content_type = "application/javascript+module"
    content_file = "src/worker.js"
  }]

  bindings = [
    {
      type = "plain_text"
      name = "DOMAIN"
      text = var.domain
    },
    {
      type = "plain_text"
      name = "CLOUDFLARE_ZONE_ID"
      text = var.cloudflare_zone_id
    },
    {
      type = "plain_text"
      name = "HOMELAB_IPV4"
      text = var.homelab_ipv4
    },
    {
      type = "plain_text"
      name = "HOMELAB_IPV6"
      text = var.homelab_ipv6
    },
    {
      type = "plain_text"
      name = "GITHUB_IPV4"
      text = var.github_ipv4
    },
    {
      type = "plain_text"
      name = "GITHUB_IPV6"
      text = var.github_ipv6
    },
    {
      type = "secret_text"
      name = "CLOUDFLARE_API_TOKEN"
      text = var.cloudflare_api_token
    },
  ]
}

resource "cloudflare_workers_deployment" "dns_failover" {
  account_id  = var.cloudflare_account_id
  script_name = cloudflare_worker.dns_failover.name
  strategy    = "percentage"

  versions = [{
    percentage = 100
    version_id = cloudflare_worker_version.dns_failover.id
  }]
}

resource "cloudflare_workers_cron_trigger" "dns_failover" {
  account_id  = var.cloudflare_account_id
  script_name = cloudflare_worker.dns_failover.name
  schedules   = ["*/1 * * * *"]
}
