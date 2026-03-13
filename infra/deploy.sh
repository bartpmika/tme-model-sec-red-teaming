#!/bin/bash
# Deploy the chat app to a Compute Engine VM (no Docker)
set -euo pipefail

PROJECT_ID="${GCP_PROJECT:-bmika-cfcd}"
ZONE="${GCP_ZONE:-us-west1-b}"
REGION="${GCP_REGION:-us-west1}"
VM_NAME="tme-model-sec-red-teaming-vm"
SERVICE_ACCOUNT="chat-app-sa@${PROJECT_ID}.iam.gserviceaccount.com"
VERTEX_ENDPOINT_ID="${VERTEX_ENDPOINT_ID:-5231372970865197056}"
MACHINE_TYPE="e2-medium"
TAG="tme-model-sec-red-teaming"
NETWORK="bmika-tme-model-sec-red-teaming"
SUBNET="bmika-tme-model-sec-red-teaming"

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
        --network "$NETWORK" \
        --subnet "$SUBNET" \
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
    "$VM_NAME":/tmp/tme-deploy/ \
    --zone "$ZONE" \
    --project "$PROJECT_ID" \
    --tunnel-through-iap

# Move code into place and restart the service
echo "Installing code and restarting service..."
gcloud compute ssh "$VM_NAME" \
    --zone "$ZONE" \
    --project "$PROJECT_ID" \
    --tunnel-through-iap \
    --command "sudo rm -rf /opt/tme-model-sec-red-teaming/backend /opt/tme-model-sec-red-teaming/frontend && \
               sudo mkdir -p /opt/tme-model-sec-red-teaming && \
               sudo mv /tmp/tme-deploy/backend /opt/tme-model-sec-red-teaming/ && \
               sudo mv /tmp/tme-deploy/frontend /opt/tme-model-sec-red-teaming/ && \
               rmdir /tmp/tme-deploy 2>/dev/null || true && \
               if [ -f /opt/tme-model-sec-red-teaming/venv/bin/pip ]; then \
                   sudo /opt/tme-model-sec-red-teaming/venv/bin/pip install -q -r /opt/tme-model-sec-red-teaming/backend/requirements.txt; \
               fi && \
               sudo systemctl restart tme-model-sec-red-teaming.service 2>/dev/null || echo 'Service not yet configured (first deploy — startup script still running). Wait a minute and re-run.'"

# Get and display external IP
EXTERNAL_IP=$(gcloud compute instances describe "$VM_NAME" \
    --zone "$ZONE" \
    --project "$PROJECT_ID" \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo "VM deployed at: https://tensorglass.com"
echo "Ensure firewall rule exists (run infra/cloud-armor-policy.sh)"
