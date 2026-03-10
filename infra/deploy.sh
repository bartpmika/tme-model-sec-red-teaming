#!/bin/bash
# Deploy the chat app to Cloud Run
set -euo pipefail

PROJECT_ID="${GCP_PROJECT:-bmika-cfcd}"
REGION="${GCP_REGION:-us-west1}"
SERVICE_NAME="prisma-chat"
SERVICE_ACCOUNT="chat-app-sa@${PROJECT_ID}.iam.gserviceaccount.com"
IMAGE="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"

# Build from project root
cd "$(dirname "$0")/.."

echo "Building container image..."
gcloud builds submit --tag "$IMAGE" --project "$PROJECT_ID"

echo "Deploying to Cloud Run..."
gcloud run deploy "$SERVICE_NAME" \
    --image "$IMAGE" \
    --region "$REGION" \
    --project "$PROJECT_ID" \
    --service-account "$SERVICE_ACCOUNT" \
    --ingress internal-and-cloud-load-balancing \
    --set-env-vars "GCP_PROJECT=${PROJECT_ID},GCP_REGION=${REGION},VERTEX_ENDPOINT_ID=${VERTEX_ENDPOINT_ID}" \
    --memory 512Mi \
    --timeout 120 \
    --no-allow-unauthenticated

echo "Deployed: $(gcloud run services describe "$SERVICE_NAME" --region "$REGION" --project "$PROJECT_ID" --format 'value(status.url)')"
