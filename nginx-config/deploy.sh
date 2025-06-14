#!/bin/bash
set -e

REPO_DIR=$1
NGINX_CONF_SRC="$REPO_DIR/nginx-config/default.conf"
NGINX_CONF_DST="/home/ubuntu/conf.d"
CERTS_DIR="/home/ubuntu/certs"
HOST_CERTS_DIR="/etc/nginx/ssl"

echo "📁 Checking and installing Docker if not present..."

if ! command -v docker &> /dev/null; then
  echo "🚀 Docker not found. Installing..."
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo "✅ Docker is already installed."
fi

# 🔁 Re-check that Docker was installed correctly
if ! command -v docker &> /dev/null; then
  echo "❌ Docker installation failed or not found. Exiting."
  exit 1
fi

echo "📁 Preparing Nginx configuration and certs..."

# Create config and certs directories
mkdir -p "$NGINX_CONF_DST"
mkdir -p "$CERTS_DIR"

# Copy Nginx config
cp "$NGINX_CONF_SRC" "$NGINX_CONF_DST/default.conf"

# Copy certificates from host location to the mount directory
echo "📜 Copying certificates..."
if [ -d "$HOST_CERTS_DIR" ]; then
  sudo cp -r "$HOST_CERTS_DIR"/* "$CERTS_DIR/"
  # Ensure proper permissions
  sudo chown -R $USER:$USER "$CERTS_DIR"
  sudo chmod 644 "$CERTS_DIR"/*.crt
  sudo chmod 600 "$CERTS_DIR"/*.key
  echo "✅ Certificates copied successfully"
else
  echo "❌ Certificate directory $HOST_CERTS_DIR not found!"
  exit 1
fi

echo "🚀 Deploying Nginx container..."

sudo docker stop mynginx || true
sudo docker rm mynginx || true

sudo docker run -d --name mynginx \
  -p 443:443 \
  -v "$NGINX_CONF_DST:/etc/nginx/conf.d" \
  -v "$CERTS_DIR:/etc/nginx/ssl" \
  nginx

echo "✅ Nginx container deployed"

# Verify the container is running
sleep 2
if sudo docker ps | grep -q mynginx; then
  echo "✅ Nginx container is running successfully"
else
  echo "❌ Nginx container failed to start. Checking logs..."
  sudo docker logs mynginx
  exit 1
fi