#!/bin/bash
# Tear down Cloud Run + LB + Cloud Armor infrastructure
# Run once before or after deploying the Compute Engine VM
set -euo pipefail

PROJECT_ID="${GCP_PROJECT:-bmika-cfcd}"
REGION="${GCP_REGION:-us-west1}"

echo "Tearing down Cloud Run + LB infrastructure..."

# 1. Forwarding rule
echo "Deleting forwarding rule..."
gcloud compute forwarding-rules delete prisma-chat-fwd \
    --project "$PROJECT_ID" --global --quiet 2>/dev/null || echo "  (not found)"

# 2. HTTP proxy
echo "Deleting HTTP proxy..."
gcloud compute target-http-proxies delete prisma-chat-https-proxy-http \
    --project "$PROJECT_ID" --quiet 2>/dev/null || echo "  (not found)"

# 3. SSL cert (if HTTPS proxy was created)
echo "Deleting SSL cert..."
gcloud compute ssl-certificates delete prisma-chat-cert \
    --project "$PROJECT_ID" --quiet 2>/dev/null || echo "  (not found)"

# 4. HTTPS proxy (if created)
echo "Deleting HTTPS proxy..."
gcloud compute target-https-proxies delete prisma-chat-https-proxy \
    --project "$PROJECT_ID" --quiet 2>/dev/null || echo "  (not found)"

# 5. URL map
echo "Deleting URL map..."
gcloud compute url-maps delete prisma-chat-urlmap \
    --project "$PROJECT_ID" --quiet 2>/dev/null || echo "  (not found)"

# 6. Backend service
echo "Deleting backend service..."
gcloud compute backend-services delete prisma-chat-backend \
    --project "$PROJECT_ID" --global --quiet 2>/dev/null || echo "  (not found)"

# 7. Serverless NEG
echo "Deleting serverless NEG..."
gcloud compute network-endpoint-groups delete prisma-chat-neg \
    --project "$PROJECT_ID" --region "$REGION" --quiet 2>/dev/null || echo "  (not found)"

# 8. Cloud Armor policy
echo "Deleting Cloud Armor policy..."
gcloud compute security-policies delete prisma-chat-policy \
    --project "$PROJECT_ID" --quiet 2>/dev/null || echo "  (not found)"

# 9. Static IP
echo "Deleting static IP..."
gcloud compute addresses delete prisma-chat-ip \
    --project "$PROJECT_ID" --global --quiet 2>/dev/null || echo "  (not found)"

# 10. Cloud Run service
echo "Deleting Cloud Run service..."
gcloud run services delete prisma-chat \
    --project "$PROJECT_ID" --region "$REGION" --quiet 2>/dev/null || echo "  (not found)"

echo "Teardown complete."
