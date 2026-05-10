#!/bin/bash
set -e

# Import existing Cloudflare resources into OpenTofu state.
# Requires: .envrc loaded (direnv) or TF_VAR_ environment variables set.

if [[ -z "$TF_VAR_cloudflare_api_token" || -z "$TF_VAR_cloudflare_account_id" || -z "$TF_VAR_cloudflare_zone_id" ]]; then
  echo "Error: TF_VAR_cloudflare_api_token, TF_VAR_cloudflare_account_id, and TF_VAR_cloudflare_zone_id must be set"
  exit 1
fi

API_TOKEN="$TF_VAR_cloudflare_api_token"
ZONE_ID="$TF_VAR_cloudflare_zone_id"
ACCOUNT_ID="$TF_VAR_cloudflare_account_id"
DOMAIN="${TF_VAR_domain:-willyhu.tw}"
CF_API="https://api.cloudflare.com/client/v4"

# Fetch DNS record IDs
echo "Fetching DNS record IDs for ${DOMAIN}..."
RECORDS=$(curl -s "${CF_API}/zones/${ZONE_ID}/dns_records?name=${DOMAIN}&order=type" \
  -H "Authorization: Bearer ${API_TOKEN}")

A_ID=$(echo "$RECORDS" | jq -r '.result[] | select(.type=="A") | .id' | head -1)
AAAA_ID=$(echo "$RECORDS" | jq -r '.result[] | select(.type=="AAAA") | .id' | head -1)

WWW_RECORDS=$(curl -s "${CF_API}/zones/${ZONE_ID}/dns_records?name=www.${DOMAIN}&type=CNAME" \
  -H "Authorization: Bearer ${API_TOKEN}")
CNAME_ID=$(echo "$WWW_RECORDS" | jq -r '.result[0].id')

echo "  A record:     ${A_ID:-not found}"
echo "  AAAA record:  ${AAAA_ID:-not found}"
echo "  CNAME record: ${CNAME_ID:-not found}"

# Fetch Worker version and deployment IDs (latest)
echo ""
echo "Fetching Worker version and deployment IDs..."
VERSION_ID=$(curl -s "${CF_API}/accounts/${ACCOUNT_ID}/workers/scripts/dns-failover/versions" \
  -H "Authorization: Bearer ${API_TOKEN}" | jq -r '.result.items[0].id')

DEPLOYMENT_ID=$(curl -s "${CF_API}/accounts/${ACCOUNT_ID}/workers/scripts/dns-failover/deployments" \
  -H "Authorization: Bearer ${API_TOKEN}" | jq -r '.result.deployments[0].id')

echo "  Worker version:    ${VERSION_ID:-not found}"
echo "  Worker deployment: ${DEPLOYMENT_ID:-not found}"

# Initialize if needed
if [[ ! -d .terraform ]]; then
  echo ""
  echo "Running tofu init..."
  tofu init
fi

# Import DNS records
echo ""
echo "Importing DNS records..."
if [[ -n "$A_ID" && "$A_ID" != "null" ]]; then
  tofu import cloudflare_dns_record.root_a "${ZONE_ID}/${A_ID}"
fi
if [[ -n "$AAAA_ID" && "$AAAA_ID" != "null" ]]; then
  tofu import cloudflare_dns_record.root_aaaa "${ZONE_ID}/${AAAA_ID}"
fi
if [[ -n "$CNAME_ID" && "$CNAME_ID" != "null" ]]; then
  tofu import cloudflare_dns_record.www_cname "${ZONE_ID}/${CNAME_ID}"
fi

# Import Worker resources
echo ""
echo "Importing Worker resources..."
tofu import cloudflare_worker.dns_failover "${ACCOUNT_ID}/dns-failover"

if [[ -n "$VERSION_ID" && "$VERSION_ID" != "null" ]]; then
  tofu import cloudflare_worker_version.dns_failover "${ACCOUNT_ID}/dns-failover/${VERSION_ID}"
fi

if [[ -n "$DEPLOYMENT_ID" && "$DEPLOYMENT_ID" != "null" ]]; then
  tofu import cloudflare_workers_deployment.dns_failover "${ACCOUNT_ID}/dns-failover/${DEPLOYMENT_ID}"
fi

tofu import 'cloudflare_workers_cron_trigger.dns_failover[0]' "${ACCOUNT_ID}/dns-failover"

echo ""
echo "Import complete. Run 'tofu plan' to verify."
