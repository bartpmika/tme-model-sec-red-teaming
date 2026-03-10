#!/bin/bash
# Set up external HTTPS LB with Cloud Armor IP allowlist for Cloud Run
set -euo pipefail

PROJECT_ID="${GCP_PROJECT:-bmika-cfcd}"
REGION="${GCP_REGION:-us-west1}"
SERVICE_NAME="prisma-chat"
POLICY_NAME="prisma-chat-policy"
NEG_NAME="prisma-chat-neg"
BACKEND_NAME="prisma-chat-backend"
URL_MAP_NAME="prisma-chat-urlmap"
PROXY_NAME="prisma-chat-https-proxy"
FWD_RULE_NAME="prisma-chat-fwd"

# Your public IP (replace before running)
MY_IP="${MY_PUBLIC_IP:?Set MY_PUBLIC_IP to your public IP address}"

echo "Creating Cloud Armor security policy..."
gcloud compute security-policies create "$POLICY_NAME" \
    --project "$PROJECT_ID" \
    --description "Allow only specific IPs to access Prisma Chat"

# Default deny
gcloud compute security-policies rules update 2147483647 \
    --security-policy "$POLICY_NAME" \
    --project "$PROJECT_ID" \
    --action deny-403

# Allow your IP
gcloud compute security-policies rules create 1000 \
    --security-policy "$POLICY_NAME" \
    --project "$PROJECT_ID" \
    --src-ip-ranges "${MY_IP}/32" \
    --action allow \
    --description "Allow my IP"

# Uncomment and set Prisma AIRS IPs when known
# gcloud compute security-policies rules create 1100 \
#     --security-policy "$POLICY_NAME" \
#     --project "$PROJECT_ID" \
#     --src-ip-ranges "PRISMA_AIRS_IP/32" \
#     --action allow \
#     --description "Allow Prisma AIRS"

echo "Creating serverless NEG..."
gcloud compute network-endpoint-groups create "$NEG_NAME" \
    --project "$PROJECT_ID" \
    --region "$REGION" \
    --network-endpoint-type serverless \
    --cloud-run-service "$SERVICE_NAME"

echo "Creating backend service..."
gcloud compute backend-services create "$BACKEND_NAME" \
    --project "$PROJECT_ID" \
    --global \
    --load-balancing-scheme EXTERNAL_MANAGED \
    --security-policy "$POLICY_NAME"

gcloud compute backend-services add-backend "$BACKEND_NAME" \
    --project "$PROJECT_ID" \
    --global \
    --network-endpoint-group "$NEG_NAME" \
    --network-endpoint-group-region "$REGION"

echo "Creating URL map and HTTPS proxy..."
gcloud compute url-maps create "$URL_MAP_NAME" \
    --project "$PROJECT_ID" \
    --default-service "$BACKEND_NAME"

# Note: You need an SSL certificate. Create one with:
# gcloud compute ssl-certificates create prisma-chat-cert --domains YOUR_DOMAIN
echo "Create an SSL certificate and then run:"
echo "  gcloud compute target-https-proxies create $PROXY_NAME --url-map $URL_MAP_NAME --ssl-certificates YOUR_CERT"
echo "  gcloud compute forwarding-rules create $FWD_RULE_NAME --global --target-https-proxy $PROXY_NAME --ports 443"
