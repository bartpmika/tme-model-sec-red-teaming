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
    --load-balancing-scheme EXTERNAL_MANAGED

gcloud compute backend-services add-backend "$BACKEND_NAME" \
    --project "$PROJECT_ID" \
    --global \
    --network-endpoint-group "$NEG_NAME" \
    --network-endpoint-group-region "$REGION"

gcloud compute backend-services update "$BACKEND_NAME" \
    --project "$PROJECT_ID" \
    --global \
    --security-policy "$POLICY_NAME"

echo "Enabling IAP on backend service..."
gcloud compute backend-services update "$BACKEND_NAME" \
    --project "$PROJECT_ID" \
    --global \
    --iap=enabled

echo "Creating URL map and HTTP proxy..."
gcloud compute url-maps create "$URL_MAP_NAME" \
    --project "$PROJECT_ID" \
    --default-service "$BACKEND_NAME"

echo "Creating HTTP proxy and forwarding rule..."
gcloud compute target-http-proxies create "${PROXY_NAME}-http" \
    --project "$PROJECT_ID" \
    --url-map "$URL_MAP_NAME"

gcloud compute addresses create prisma-chat-ip \
    --project "$PROJECT_ID" \
    --global

gcloud compute forwarding-rules create "$FWD_RULE_NAME" \
    --project "$PROJECT_ID" \
    --global \
    --target-http-proxy "${PROXY_NAME}-http" \
    --ports 80 \
    --address prisma-chat-ip \
    --load-balancing-scheme EXTERNAL_MANAGED

LB_IP=$(gcloud compute addresses describe prisma-chat-ip --project "$PROJECT_ID" --global --format="value(address)")
echo "Load balancer IP: $LB_IP"
echo "Cloud Armor + IAP are active. Access via browser at http://$LB_IP"
