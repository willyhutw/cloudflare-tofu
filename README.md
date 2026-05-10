# Cloudflare OpenTofu

Manage Cloudflare DNS records and DNS failover Worker with OpenTofu.

```
Cron (every 5 min) → Worker checks homelab /health via TCP
  ├── UP   → DNS A/AAAA → homelab IP  (proxied=true,  hides real IP behind CF)
  └── DOWN → DNS A/AAAA → GitHub Pages IP (proxied=false, required by GitHub Pages)
```

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.6.0
- [direnv](https://direnv.net/)
- `jq` and `curl` (for import script)
- Cloudflare API token with Zone:DNS:Edit, Zone:Zone:Read, Workers Scripts:Edit

## Setup

1. Configure sensitive variables via [direnv](https://direnv.net/) (API token, account/zone ID, homelab IPs):

```bash
cp .envrc.example .envrc
# Edit .envrc with your values
direnv allow
```

2. Configure non-sensitive variables in tfvars (domain, GitHub Pages IPs):

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars if needed
```

## Usage

```bash
tofu init
tofu plan
tofu apply
```

## Import Existing Resources

If resources already exist in Cloudflare (e.g. after OS reinstall and state is lost), import them into OpenTofu state before applying:

```bash
./import.sh
```

The script automatically:

1. Fetches DNS record IDs from Cloudflare API via `curl` + `jq`
2. Fetches the latest Worker version and deployment IDs
3. Runs `tofu init` if not already initialized
4. Imports all DNS records (A, AAAA, CNAME) and Worker resources (script, version, deployment, cron trigger)

After import, run `tofu plan` to verify state matches the actual resources.

## Project Structure

```
cloudflare-tofu/
├── main.tf                    # Provider configuration
├── variables.tf               # Variable definitions
├── dns.tf                     # A, AAAA, CNAME records
├── worker.tf                  # Worker script, deployment, cron trigger
├── outputs.tf                 # Worker name, DNS record IDs
├── terraform.tfvars.example   # Example variable values (tfvars)
├── .envrc.example             # Example variable values (direnv)
├── import.sh                  # Import existing resources into state
└── src/
    └── worker.js              # DNS failover Worker script
```

## DNS Failover Worker

The failover Worker is disabled by default. To enable/disable:

```bash
# Disable
tofu apply -var="worker_enabled=false"

# Enable (default)
tofu apply
```

This only controls the cron trigger. The Worker script and DNS records are unaffected.

## Notes

- A/AAAA record `content`, `proxied`, and `ttl` are managed by the Worker at runtime. OpenTofu ignores drift on these fields via `lifecycle { ignore_changes }`.
- When pointing to homelab, `proxied=true` hides the real IP behind Cloudflare edges. When pointing to GitHub Pages, `proxied=false` is required for GitHub Pages to function correctly.
- CNAME (`www` → root domain) is fully managed by OpenTofu.
