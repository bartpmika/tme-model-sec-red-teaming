#!/bin/bash
# Deploy the chat app to a Compute Engine VM (no Docker)
set -euo pipefail

PROJECT_ID="${GCP_PROJECT:-bmika-cfcd}"
ZONE="${GCP_ZONE:-us-west1-b}"
REGION="${GCP_REGION:-us-west1}"
VM_NAME="prisma-chat-vm"
SERVICE_ACCOUNT="chat-app-sa@${PROJECT_ID}.iam.gserviceaccount.com"
VERTEX_ENDPOINT_ID="${VERTEX_ENDPOINT_ID:-5231372970865197056}"
MACHINE_TYPE="e2-small"
TAG="prisma-chat-server"

cd "$(dirname "$0")/.."

# Check if VM already exists
if gcloud compute instances describe "$VM_NAME" --zone "$ZONE" --project "$PROJECT_ID" &>/dev/null; then
    echo "VM $VM_NAME already exists. Updating code..."
else
    echo "Creating VM $VM_NAME..."
    gcloud compute instances create "$VM_NAME" \
        --zone "$ZONE" \
        --project "$PROJECT_ID" \
        --machine-type "$MACHINE_TYPE" \
        --service-account "$SERVICE_ACCOUNT" \
        --scopes cloud-platform \
        --tags "$TAG" \
        --image-family debian-12 \
        --image-project debian-cloud \
        --metadata "GCP_PROJECT=${PROJECT_ID},GCP_REGION=${REGION},VERTEX_ENDPOINT_ID=${VERTEX_ENDPOINT_ID}" \
        --metadata-from-file startup-script=infra/startup.sh

    echo "Waiting for VM to boot and run startup script..."
    sleep 30
fi

# Copy application code to the VM
echo "Copying application code..."
gcloud compute scp --recurse \
    backend/ frontend/ \
    "$VM_NAME":/tmp/prisma-chat-deploy/ \
    --zone "$ZONE" \
    --project "$PROJECT_ID"

# Move code into place and restart the service
echo "Installing code and restarting service..."
gcloud compute ssh "$VM_NAME" \
    --zone "$ZONE" \
    --project "$PROJECT_ID" \
    --command "sudo rm -rf /opt/prisma-chat/backend /opt/prisma-chat/frontend && \
               sudo mkdir -p /opt/prisma-chat && \
               sudo mv /tmp/prisma-chat-deploy/backend /opt/prisma-chat/ && \
               sudo mv /tmp/prisma-chat-deploy/frontend /opt/prisma-chat/ && \
               rmdir /tmp/prisma-chat-deploy 2>/dev/null || true && \
               if [ -f /opt/prisma-chat/venv/bin/pip ]; then \
                   sudo /opt/prisma-chat/venv/bin/pip install -q -r /opt/prisma-chat/backend/requirements.txt; \
               fi && \
               sudo systemctl restart prisma-chat.service 2>/dev/null || echo 'Service not yet configured (first deploy — startup script still running). Wait a minute and re-run.'"

# Get and display external IP
EXTERNAL_IP=$(gcloud compute instances describe "$VM_NAME" \
    --zone "$ZONE" \
    --project "$PROJECT_ID" \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo "VM deployed at: http://${EXTERNAL_IP}"
echo "Ensure firewall rule exists (run infra/cloud-armor-policy.sh)"
