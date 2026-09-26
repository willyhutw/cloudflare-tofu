# Cloudflare OpenTofu

Manage Cloudflare DNS records, DNS failover Worker, and R2 backup bucket with OpenTofu.

```
Cron (every 5 min) → Worker checks homelab /health via TCP
  ├── UP   → willyhu.tw A/AAAA → homelab IP      (proxied=true,  hides real IP behind CF)
  └── DOWN → willyhu.tw A/AAAA → GitHub Pages IP (proxied=false, required by GitHub Pages)

www.willyhu.tw CNAME → willyhu.tw (always proxied=true)
  ├── Homelab UP:   CF proxy → homelab
  └── Homelab DOWN: CF proxy → GitHub Pages  (GitHub Pages supports CF proxy on www)
```

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.6.0
- [direnv](https://direnv.net/)
- `jq` and `curl` (for import script)
- Cloudflare API token with Zone:DNS:Edit, Zone:Zone:Read, Workers Scripts:Edit, and account-level Workers R2 Storage:Edit
- R2 enabled on the Cloudflare account (Dashboard → R2). Bucket creation fails otherwise.

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
├── r2.tf                      # R2 backup bucket and lifecycle rules
├── outputs.tf                 # Worker name, DNS record IDs, R2 bucket name
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

## R2 Backup Bucket

`r2.tf` creates the R2 bucket `willy-homelab-backup` (location hint `apac`). It is the off-site destination for the homelab micro cluster's etcd snapshots and PKI backups, uploaded from control-plane nodes.

> **R2 must be enabled on the Cloudflare account before `tofu apply`**, otherwise bucket creation fails.

Lifecycle rules (`cloudflare_r2_bucket_lifecycle`):

| Prefix   | Rule                                           |
|----------|------------------------------------------------|
| `micro/` | Delete objects 7 days after upload             |
| `micro/` | Abort incomplete multipart uploads after 1 day |

R2 lifecycle `max_age` is in **seconds**, not days (see `local.one_day_seconds` in `r2.tf`).

### S3 credentials for uploads

The OpenTofu API token only manages the bucket. Uploads use a separate R2 S3 credential, which is **not managed here and must never be committed to Git**:

1. Cloudflare Dashboard → R2 → Manage API Tokens → Create API token
2. Permission: `Object Read & Write`, scoped to the `willy-homelab-backup` bucket only
3. Store the Access Key ID and Secret Access Key on the control-plane nodes (outside this repo)
4. S3 endpoint: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` (region `auto`)

```bash
aws s3 cp etcd-snapshot.db s3://willy-homelab-backup/micro/etcd/ \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

## Notes

- A/AAAA record `content`, `proxied`, and `ttl` are managed by the Worker at runtime. OpenTofu ignores drift on these fields via `lifecycle { ignore_changes }`.
- When pointing to homelab, `proxied=true` hides the real IP behind Cloudflare edges. When pointing to GitHub Pages, `proxied=false` is required for the apex domain.
- `www.willyhu.tw` CNAME is permanently `proxied=true`. When DNS fails over to GitHub Pages, Cloudflare proxies `www` traffic to GitHub Pages, which supports this setup as long as `www.willyhu.tw` is configured as a custom domain in the GitHub Pages settings.
- CNAME (`www` → root domain) is fully managed by OpenTofu.
