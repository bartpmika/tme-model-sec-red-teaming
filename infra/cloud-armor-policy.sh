#!/bin/bash
# Create GCP firewall rule to allowlist IPs for the chat app VM
set -euo pipefail

PROJECT_ID="${GCP_PROJECT:-bmika-cfcd}"
RULE_NAME="allow-tme-model-sec-red-teaming"
TAG="tme-model-sec-red-teaming"

# IPs to allow
ALLOWED_IPS="199.167.52.5/32,66.8.253.50/32"

echo "Creating firewall rule ${RULE_NAME}..."

# Delete existing rule if present (idempotent)
gcloud compute firewall-rules delete "$RULE_NAME" \
    --project "$PROJECT_ID" --quiet 2>/dev/null || true

gcloud compute firewall-rules create "$RULE_NAME" \
    --project "$PROJECT_ID" \
    --direction INGRESS \
    --action ALLOW \
    --rules tcp:80,tcp:8080 \
    --source-ranges "$ALLOWED_IPS" \
    --target-tags "$TAG" \
    --network bmika-tme-model-sec-red-teaming \
    --description "Allow specific IPs to access TME Model Sec Red Teaming VM"

echo "Firewall rule created. Allowed IPs: ${ALLOWED_IPS}"
echo "Targets VMs with network tag: ${TAG}"
