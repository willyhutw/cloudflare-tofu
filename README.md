# Cloudflare OpenTofu

Manage Cloudflare DNS records, DNS failover Worker, and R2 buckets (homelab backups + OpenTofu remote state) with OpenTofu.

```
Cron (every 5 min) → Worker checks homelab /health via TCP
  ├── UP   → willyhu.tw A/AAAA → homelab IP      (proxied=true,  hides real IP behind CF)
  └── DOWN → willyhu.tw A/AAAA → GitHub Pages IP (proxied=false, required by GitHub Pages)

www.willyhu.tw CNAME → willyhu.tw (always proxied=true)
  ├── Homelab UP:   CF proxy → homelab
  └── Homelab DOWN: CF proxy → GitHub Pages  (GitHub Pages supports CF proxy on www)
```

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.10.0 (S3 backend `use_lockfile`)
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

3. Configure the R2 state backend (see [Remote State on R2](#remote-state-on-r2)):

```bash
cp backend.hcl.example backend.hcl
# Replace <ACCOUNT_ID>; set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in .envrc
```

## Usage

```bash
tofu init -backend-config=backend.hcl
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
3. Runs `tofu init` if not already initialized (`-backend-config=backend.hcl` if present, otherwise `-backend=false` with local state)
4. Imports all DNS records (A, AAAA, CNAME) and Worker resources (script, version, deployment, cron trigger)

After import, run `tofu plan` to verify state matches the actual resources.

## Project Structure

```
cloudflare-tofu/
├── main.tf                    # Provider + S3 backend (partial) configuration
├── variables.tf               # Variable definitions
├── dns.tf                     # A, AAAA, CNAME records
├── worker.tf                  # Worker script, deployment, cron trigger
├── r2.tf                      # R2 backup + state buckets and lifecycle rules
├── outputs.tf                 # Worker name, DNS record IDs, R2 bucket names
├── terraform.tfvars.example   # Example variable values (tfvars)
├── .envrc.example             # Example variable values (direnv)
├── backend.hcl.example        # Example R2 S3 backend config (copy to backend.hcl)
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

## R2 Buckets

`r2.tf` creates two R2 buckets (location hint `apac`):

| Bucket                     | Role                                                           | Lifecycle                                                          |
|----------------------------|----------------------------------------------------------------|--------------------------------------------------------------------|
| `willyhutw-homelab-backup` | Off-site etcd snapshots + PKI backups from control-plane nodes | `micro/`: delete after 7 days; abort multipart uploads after 1 day |
| `willyhutw-tofu-state`     | OpenTofu remote state for this repo                            | Abort multipart uploads after 1 day only (**no expiry**, state is kept forever) |

- `willyhutw-tofu-state` has `lifecycle { prevent_destroy = true }`, so OpenTofu refuses to destroy or replace it.
- R2 lifecycle `max_age` is in **seconds**, not days (see `local.one_day_seconds` in `r2.tf`).

> **R2 must be enabled on the Cloudflare account before `tofu apply`**, otherwise bucket creation fails.

### R2 S3 credentials

The OpenTofu API token only manages the buckets. Object access uses R2 S3 credentials, which are **not managed here and must never be committed to Git**. Create **two** tokens so each can be rotated independently (Dashboard → R2 → Manage API Tokens → Create API token, permission `Object Read & Write`):

| Token         | Scoped to                  | Stored in                                                 |
|---------------|----------------------------|-----------------------------------------------------------|
| State backend | `willyhutw-tofu-state`     | `.envrc` as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` |
| Backup upload | `willyhutw-homelab-backup` | Control-plane nodes (outside this repo)                   |

S3 endpoint: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` (region `auto`).

```bash
aws s3 cp etcd-snapshot.db s3://willyhutw-homelab-backup/micro/etcd/ \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

## Remote State on R2

`main.tf` declares an empty `backend "s3" {}` (partial configuration). The actual settings live in the gitignored `backend.hcl`, copied from `backend.hcl.example`. Locking uses OpenTofu's S3-native lock file (`use_lockfile = true`), no DynamoDB needed.

### First-time bootstrap

The state bucket is managed by this repo, so it must exist before the state can move into it:

```bash
# 1. Init without backend (state stays local)
tofu init -backend=false

# 2. Create only the R2 resources, state still local
tofu apply \
  -target=cloudflare_r2_bucket.homelab_backup \
  -target=cloudflare_r2_bucket_lifecycle.homelab_backup \
  -target=cloudflare_r2_bucket.tofu_state \
  -target=cloudflare_r2_bucket_lifecycle.tofu_state

# 3. Create the state-backend R2 S3 token (see above), put AWS_* in .envrc, then direnv allow
cp backend.hcl.example backend.hcl   # replace <ACCOUNT_ID>

# 4. Migrate local state into R2
tofu init -migrate-state -backend-config=backend.hcl

# 5. Verify
tofu plan
```

After migration, the local `terraform.tfstate*` files are no longer used.

### Reinstall / new machine

Restore `.envrc` and `backend.hcl` (both gitignored, e.g. from a password manager or synced storage), then:

```bash
direnv allow
tofu init -backend-config=backend.hcl
tofu plan
```

No `./import.sh` is needed once state lives in R2.

## Notes

- A/AAAA record `content`, `proxied`, and `ttl` are managed by the Worker at runtime. OpenTofu ignores drift on these fields via `lifecycle { ignore_changes }`.
- When pointing to homelab, `proxied=true` hides the real IP behind Cloudflare edges. When pointing to GitHub Pages, `proxied=false` is required for the apex domain.
- `www.willyhu.tw` CNAME is permanently `proxied=true`. When DNS fails over to GitHub Pages, Cloudflare proxies `www` traffic to GitHub Pages, which supports this setup as long as `www.willyhu.tw` is configured as a custom domain in the GitHub Pages settings.
- CNAME (`www` → root domain) is fully managed by OpenTofu.
