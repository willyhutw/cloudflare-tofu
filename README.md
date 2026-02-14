# Cloudflare OpenTofu

Manage Cloudflare DNS records and DNS failover Worker with OpenTofu.

```
Cron (every minute) → Worker checks homelab /health
  ├── UP   → DNS A/AAAA → homelab IP
  └── DOWN → DNS A/AAAA → GitHub Pages IP
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
2. Runs `tofu init` if not already initialized
3. Imports all DNS records (A, AAAA, CNAME) and Worker resources

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

## Notes

- A/AAAA record content is managed by the Worker at runtime. OpenTofu ignores content drift via `lifecycle { ignore_changes }`.
- CNAME (`www` → root domain) is fully managed by OpenTofu.
