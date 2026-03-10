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
VERTEX_ENDPOINT_ID=$(curl -sf -H "$META_HEADER" "$META_URL/VERTEX_ENDPOINT_ID" || echo "")

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
Environment=VERTEX_ENDPOINT_ID=${VERTEX_ENDPOINT_ID}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tme-model-sec-red-teaming.service
systemctl restart tme-model-sec-red-teaming.service
