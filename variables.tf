variable "cloudflare_api_token" {
  description = "Cloudflare API token (Zone:DNS:Edit, Zone:Zone:Read, Workers Scripts:Edit)"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the domain"
  type        = string
}

variable "domain" {
  description = "Root domain name"
  type        = string
  default     = "willyhu.tw"
}

variable "homelab_ipv4" {
  description = "Homelab public IPv4 address"
  type        = string
}

variable "homelab_ipv6" {
  description = "Homelab public IPv6 address"
  type        = string
}

variable "github_ipv4" {
  description = "GitHub Pages IPv4 address"
  type        = string
  default     = "185.199.108.153"
}

variable "github_ipv6" {
  description = "GitHub Pages IPv6 address"
  type        = string
  default     = "2606:50c0:8000::153"
}

variable "worker_enabled" {
  description = "Enable or disable the DNS failover Worker cron trigger"
  type        = bool
  default     = true
}
