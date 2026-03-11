#!/bin/bash
# VM startup script — installs dependencies and configures systemd service
set -euo pipefail

APP_DIR="/opt/tme-model-sec-red-teaming"

# Install system packages
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv > /dev/null

# Create app directory and venv
mkdir -p "$APP_DIR"
if [ ! -d "$APP_DIR/venv" ]; then
    python3 -m venv "$APP_DIR/venv"
fi

# Install Python dependencies if requirements.txt exists
if [ -f "$APP_DIR/backend/requirements.txt" ]; then
    "$APP_DIR/venv/bin/pip" install -q -r "$APP_DIR/backend/requirements.txt"
fi

# Read env vars from instance metadata
META_URL="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
META_HEADER="Metadata-Flavor: Google"
GCP_PROJECT=$(curl -sf -H "$META_HEADER" "$META_URL/GCP_PROJECT" || echo "")
GCP_REGION=$(curl -sf -H "$META_HEADER" "$META_URL/GCP_REGION" || echo "")
# Write systemd unit
cat > /etc/systemd/system/tme-model-sec-red-teaming.service <<EOF
[Unit]
Description=TME Model Sec Red Teaming App
After=network.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/venv/bin/gunicorn --bind 0.0.0.0:80 --workers 2 --timeout 120 backend.app:app
Environment=GCP_PROJECT=${GCP_PROJECT}
Environment=GCP_REGION=${GCP_REGION}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tme-model-sec-red-teaming.service
systemctl restart tme-model-sec-red-teaming.service

# ── k3s installation (Traefik disabled to avoid port 80 conflict) ──
if ! command -v k3s &>/dev/null; then
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Wait for k3s to be ready
echo "Waiting for k3s node to be ready..."
until k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; do
    sleep 5
done
echo "k3s is ready."

# ── Fetch PANW secrets from GCP Secret Manager ──
REGISTRY_USER=$(gcloud secrets versions access latest --secret=panw-registry-username --project="$GCP_PROJECT")
REGISTRY_PASS=$(gcloud secrets versions access latest --secret=panw-registry-password --project="$GCP_PROJECT")
CLIENT_ID=$(gcloud secrets versions access latest --secret=panw-client-id --project="$GCP_PROJECT")
CLIENT_SECRET=$(gcloud secrets versions access latest --secret=panw-client-secret --project="$GCP_PROJECT")
CHANNEL_ID="6ff54413-ce3f-47f6-b081-ea1ef98f5941"

# ── Create Kubernetes docker-registry pull secret ──
k3s kubectl delete secret airs-pull-secret --ignore-not-found
k3s kubectl create secret docker-registry airs-pull-secret \
    --docker-server=registry.ai-red-teaming.paloaltonetworks.com \
    --docker-username="$REGISTRY_USER" \
    --docker-password="$REGISTRY_PASS"

# ── Install Helm ──
if ! command -v helm &>/dev/null; then
    curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# ── Deploy panw-network-client Helm chart ──
echo "$REGISTRY_PASS" | helm registry login registry.ai-red-teaming.paloaltonetworks.com \
    --username "$REGISTRY_USER" \
    --password-stdin

helm upgrade --install panw-network-client \
    oci://registry.ai-red-teaming.paloaltonetworks.com/pairs-redteam-prd-fckx/red-teaming-onprem/charts/panw-network-client \
    --version 1.0.4 \
    --kubeconfig /etc/rancher/k3s/k3s.yaml \
    --set config.clientId="$CLIENT_ID" \
    --set config.clientSecret="$CLIENT_SECRET" \
    --set config.channelId="$CHANNEL_ID"

echo "panw-network-client deployed successfully."
