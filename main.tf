terraform {
  required_version = ">= 1.10.0"

  # Partial config: values come from backend.hcl (see backend.hcl.example).
  backend "s3" {}

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
