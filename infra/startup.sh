#!/bin/bash
# VM startup script — installs dependencies and configures systemd service
set -euo pipefail

APP_DIR="/opt/tme-model-sec-red-teaming"

# Install system packages
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv nginx certbot python3-certbot-dns-google > /dev/null

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

# Fetch app auth secrets from GCP Secret Manager (uses printf to preserve $ in hashes)
APP_SECRET_KEY=$(gcloud secrets versions access latest --secret=app-secret-key --project="$GCP_PROJECT")
APP_USERNAME=$(gcloud secrets versions access latest --secret=app-auth-username --project="$GCP_PROJECT")
APP_PASSWORD_HASH=$(gcloud secrets versions access latest --secret=app-auth-password-hash --project="$GCP_PROJECT")
OAUTH_CLIENT_ID_VAL=$(gcloud secrets versions access latest --secret=oauth-client-id --project="$GCP_PROJECT")
OAUTH_CLIENT_SECRET_VAL=$(gcloud secrets versions access latest --secret=oauth-client-secret --project="$GCP_PROJECT")

# Write env file (EnvironmentFile avoids systemd $ interpolation issues)
ENV_FILE="${APP_DIR}/app.env"
printf 'GCP_PROJECT=%s\n' "$GCP_PROJECT" > "$ENV_FILE"
printf 'GCP_REGION=%s\n' "$GCP_REGION" >> "$ENV_FILE"
printf 'APP_SECRET_KEY=%s\n' "$APP_SECRET_KEY" >> "$ENV_FILE"
printf 'APP_USERNAME=%s\n' "$APP_USERNAME" >> "$ENV_FILE"
printf 'APP_PASSWORD_HASH=%s\n' "$APP_PASSWORD_HASH" >> "$ENV_FILE"
printf 'OAUTH_CLIENT_ID=%s\n' "$OAUTH_CLIENT_ID_VAL" >> "$ENV_FILE"
printf 'OAUTH_CLIENT_SECRET=%s\n' "$OAUTH_CLIENT_SECRET_VAL" >> "$ENV_FILE"
chmod 600 "$ENV_FILE"

# Write systemd unit
cat > /etc/systemd/system/tme-model-sec-red-teaming.service <<'UNIT'
[Unit]
Description=TME Model Sec Red Teaming App
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/tme-model-sec-red-teaming
ExecStart=/opt/tme-model-sec-red-teaming/venv/bin/gunicorn --bind 127.0.0.1:8080 --workers 2 --timeout 120 backend.app:app
EnvironmentFile=/opt/tme-model-sec-red-teaming/app.env
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable tme-model-sec-red-teaming.service
systemctl restart tme-model-sec-red-teaming.service

# ── TLS via Let's Encrypt (DNS-01 challenge) ──
DOMAIN="tensorglass.com"
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

if [ ! -f "$CERT_PATH" ]; then
    certbot certonly \
        --dns-google \
        -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --keep-until-expiring
fi

cat > /etc/nginx/sites-available/tme-model-sec-red-teaming <<'NGINX'
server {
    listen 80 default_server;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;

    ssl_certificate     /etc/letsencrypt/live/tensorglass.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tensorglass.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
    }
}
NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/tme-model-sec-red-teaming /etc/nginx/sites-enabled/
nginx -t && systemctl enable nginx && systemctl restart nginx

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
