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

If resources already exist in Cloudflare but **no state exists anywhere** (neither locally nor in the R2 state bucket), import them into OpenTofu state before applying:

```bash
./import.sh
```

The script automatically:

1. Fetches DNS record IDs from Cloudflare API via `curl` + `jq`
2. Fetches the latest Worker version and deployment IDs
3. Runs `tofu init` if not already initialized, before any import:
   - `backend.hcl` present → `tofu init -backend-config=backend.hcl` (R2 remote state)
   - `backend "s3"` commented out in `main.tf` → `tofu init -backend=false` (local state)
   - otherwise → prints the fix-up recipe and exits 1 (see [Why not just `-backend=false`?](#why-not-just--backendfalse))
4. Imports all DNS records (A, AAAA, CNAME) and Worker resources (script, version, deployment, cron trigger)

After import, run `tofu plan` to verify state matches the actual resources.

> If the state is only lost locally but still in R2, do **not** import; see [State lost locally, state bucket intact](#state-lost-locally-state-bucket-intact).

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

### Why not just `-backend=false`?

While `main.tf` declares `backend "s3" {}`, `tofu init -backend=false` (with or without `-reconfigure`) prints "OpenTofu has been successfully initialized!", but every later `tofu plan` / `apply` / `import` / `state list` fails with:

```
Error: Backend initialization required, please run "tofu init"
Reason: Initial configuration of the requested backend "s3"
```

So to work with **local** state (only needed before the state bucket exists), the backend block must be commented out temporarily.

### First-time bootstrap

The state bucket is managed by this repo, so it has to be created with local state first, then the state is migrated into it:

```bash
# 1. Temporarily disable the backend block (otherwise step 3 fails, see above)
sed -i 's|^  backend "s3" {}|  # backend "s3" {}  # TEMP: local state for bootstrap|' main.tf

# 2. Init with local state
tofu init -backend=false

# 3. Create the resources (incl. both R2 buckets); state is written to ./terraform.tfstate
tofu plan
tofu apply

# 4. Restore the backend block
git checkout -- main.tf

# 5. Create the state-backend R2 S3 token (see "R2 S3 credentials"),
#    put AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in .envrc, then:
direnv allow
cp backend.hcl.example backend.hcl   # replace <ACCOUNT_ID>

# 6. Move the local state into R2 (answer "yes" to copy existing state)
tofu init -migrate-state -backend-config=backend.hcl

# 7. Verify: should report "No changes"
tofu plan
```

After migration, the local `terraform.tfstate*` files are no longer used (keep a copy until `tofu plan` is clean, then delete them).

### Daily use / reinstall / new machine

Restore `.envrc` (incl. `AWS_*`) and `backend.hcl` (both gitignored, e.g. from a password manager or synced storage), then:

```bash
direnv allow
tofu init -backend-config=backend.hcl
tofu plan
```

### State lost locally, state bucket intact

Losing the local checkout / `.terraform/` does **not** lose the state; it lives in `willyhutw-tofu-state`. Do **not** use `-backend=false` and do **not** run `./import.sh`; just reconnect to R2:

```bash
cp backend.hcl.example backend.hcl   # replace <ACCOUNT_ID>, if backend.hcl was lost too
# restore AWS_* in .envrc (or create a new state-backend R2 S3 token), then:
direnv allow
tofu init -backend-config=backend.hcl   # add -reconfigure if .terraform/ points elsewhere
tofu state list                         # resources should be listed
tofu plan
```

Only if the state object itself is gone from R2 (or the bucket is gone) fall back to `./import.sh` (with `backend.hcl` if the bucket still exists, otherwise via [First-time bootstrap](#first-time-bootstrap)).

## Notes

- A/AAAA record `content`, `proxied`, and `ttl` are managed by the Worker at runtime. OpenTofu ignores drift on these fields via `lifecycle { ignore_changes }`.
- When pointing to homelab, `proxied=true` hides the real IP behind Cloudflare edges. When pointing to GitHub Pages, `proxied=false` is required for the apex domain.
- `www.willyhu.tw` CNAME is permanently `proxied=true`. When DNS fails over to GitHub Pages, Cloudflare proxies `www` traffic to GitHub Pages, which supports this setup as long as `www.willyhu.tw` is configured as a custom domain in the GitHub Pages settings.
- CNAME (`www` → root domain) is fully managed by OpenTofu.
