#!/bin/bash
# Deploy the chat app to a Compute Engine VM
set -euo pipefail

PROJECT_ID="${GCP_PROJECT:-bmika-cfcd}"
ZONE="${GCP_ZONE:-us-west1-b}"
REGION="${GCP_REGION:-us-west1}"
VM_NAME="prisma-chat-vm"
SERVICE_ACCOUNT="chat-app-sa@${PROJECT_ID}.iam.gserviceaccount.com"
VERTEX_ENDPOINT_ID="${VERTEX_ENDPOINT_ID:-5231372970865197056}"
MACHINE_TYPE="e2-small"
IMAGE_NAME="prisma-chat"
TAG="prisma-chat-server"

cd "$(dirname "$0")/.."

# Build and push container image to GCR
echo "Building and pushing container image..."
gcloud builds submit \
    --project "$PROJECT_ID" \
    --tag "gcr.io/${PROJECT_ID}/${IMAGE_NAME}" \
    -f backend/Dockerfile .

# Check if VM already exists
if gcloud compute instances describe "$VM_NAME" --zone "$ZONE" --project "$PROJECT_ID" &>/dev/null; then
    echo "VM $VM_NAME already exists. Updating container..."
    gcloud compute instances update-container "$VM_NAME" \
        --zone "$ZONE" \
        --project "$PROJECT_ID" \
        --container-image "gcr.io/${PROJECT_ID}/${IMAGE_NAME}" \
        --container-env "GCP_PROJECT=${PROJECT_ID},GCP_REGION=${REGION},VERTEX_ENDPOINT_ID=${VERTEX_ENDPOINT_ID},PORT=80"
else
    echo "Creating VM $VM_NAME..."
    gcloud compute instances create-with-container "$VM_NAME" \
        --zone "$ZONE" \
        --project "$PROJECT_ID" \
        --machine-type "$MACHINE_TYPE" \
        --service-account "$SERVICE_ACCOUNT" \
        --scopes cloud-platform \
        --tags "$TAG" \
        --image-family cos-stable \
        --image-project cos-cloud \
        --container-image "gcr.io/${PROJECT_ID}/${IMAGE_NAME}" \
        --container-env "GCP_PROJECT=${PROJECT_ID},GCP_REGION=${REGION},VERTEX_ENDPOINT_ID=${VERTEX_ENDPOINT_ID},PORT=80"
fi

# Get and display external IP
EXTERNAL_IP=$(gcloud compute instances describe "$VM_NAME" \
    --zone "$ZONE" \
    --project "$PROJECT_ID" \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo "VM deployed at: http://${EXTERNAL_IP}"
echo "Ensure firewall rule exists (run infra/firewall-rules.sh)"
