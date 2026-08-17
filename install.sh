#!/bin/bash
set -e

# Open Helpdesk - Full Installation Script
# Installs backend + client on a single server with PostgreSQL and nginx.
# Requirements: Node.js 22+, PostgreSQL 15+, nginx.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Hyzokaaa/open-helpdesk/main/install.sh | bash
#
# Or clone the repo and run:
#   chmod +x install.sh && ./install.sh

INSTALL_DIR="/opt/open-helpdesk"
WEB_ROOT="/var/www/openhelpdesk"
SERVICE_USER="openhelpdesk"
SERVICE_NAME="openhelpdesk-backend"

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║     Open Helpdesk Installer          ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# ── Check Node.js ──

if ! command -v node &> /dev/null; then
  echo "[ERROR] Node.js is not installed."
  echo ""
  echo "  Install Node.js 22+:"
  echo "    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
  echo "    sudo apt-get install -y nodejs"
  echo ""
  exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 22 ]; then
  echo "[ERROR] Node.js 22+ required. Found: $(node -v)"
  exit 1
fi
echo "[OK] Node.js $(node -v)"

# ── Check PostgreSQL ──

if ! command -v psql &> /dev/null; then
  echo "[ERROR] PostgreSQL is not installed."
  echo ""
  echo "  Install PostgreSQL:"
  echo "    sudo apt-get install -y postgresql"
  echo ""
  exit 1
fi
echo "[OK] PostgreSQL found"

# ── Check nginx ──

if ! command -v nginx &> /dev/null; then
  echo "[ERROR] nginx is not installed."
  echo ""
  echo "  Install nginx:"
  echo "    sudo apt-get install -y nginx"
  echo ""
  exit 1
fi
echo "[OK] nginx found"

# ── Configuration ──

echo ""
echo "── Configuration ──"
echo ""

read -p "Server hostname (e.g. helpdesk.yourcompany.com): " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-localhost}

read -p "Database host [localhost]: " DB_HOST
DB_HOST=${DB_HOST:-localhost}

read -p "Database port [5432]: " DB_PORT
DB_PORT=${DB_PORT:-5432}

read -p "Database name [open_helpdesk]: " DB_NAME
DB_NAME=${DB_NAME:-open_helpdesk}

read -p "Database user [postgres]: " DB_USER
DB_USER=${DB_USER:-postgres}

read -sp "Database password: " DB_PASSWORD
echo ""

read -p "Admin email [admin@admin.com]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@admin.com}

read -sp "Admin password [admin1234]: " ADMIN_PASSWORD
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin1234}
echo ""

read -p "App name [Open Helpdesk]: " APP_NAME
APP_NAME=${APP_NAME:-Open Helpdesk}

JWT_SECRET=$(openssl rand -hex 32)

# Determine URLs based on hostname
if [ "$SERVER_NAME" = "localhost" ]; then
  FRONTEND_URL="http://localhost"
  VITE_API_URL="http://localhost/api"
else
  FRONTEND_URL="https://$SERVER_NAME"
  VITE_API_URL="https://$SERVER_NAME/api"
fi

echo ""
echo "── Installing Backend ──"
echo ""

# ── Create system user ──

if ! id "$SERVICE_USER" &> /dev/null; then
  sudo useradd --system --no-create-home --shell /bin/false "$SERVICE_USER" 2>/dev/null || true
fi

# ── Clone and build backend ──

sudo mkdir -p "$INSTALL_DIR"

if [ -d "$INSTALL_DIR/backend/.git" ]; then
  echo "Updating backend..."
  cd "$INSTALL_DIR/backend"
  sudo git pull
else
  echo "Cloning backend..."
  sudo git clone https://github.com/Hyzokaaa/open-helpdesk-backend.git "$INSTALL_DIR/backend"
fi

cd "$INSTALL_DIR/backend"
echo "Installing dependencies..."
sudo npm install --production=false 2>&1 | tail -1
echo "Building..."
sudo npm run build 2>&1 | tail -1

# ── Create backend .env ──

sudo mkdir -p "$INSTALL_DIR/backend/data/storage"

if [ ! -f "$INSTALL_DIR/backend/.env" ]; then
  sudo tee "$INSTALL_DIR/backend/.env" > /dev/null << EOF
PORT=3000
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_RUN_MIGRATIONS=true
JWT_SECRET=$JWT_SECRET
JWT_EXPIRATION=1d
FRONTEND_URL=$FRONTEND_URL
STORAGE_PROVIDER=filesystem
STORAGE_PATH=$INSTALL_DIR/backend/data/storage
ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_PASSWORD=$ADMIN_PASSWORD
EOF
  echo "[OK] Backend config saved"
else
  echo "[OK] Using existing backend .env"
fi

sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/backend" 2>/dev/null || true

# ── Create systemd service ──

sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null << EOF
[Unit]
Description=Open Helpdesk Backend
After=postgresql.service network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/backend
EnvironmentFile=$INSTALL_DIR/backend/.env
ExecStart=$(which node) $INSTALL_DIR/backend/dist/main
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME" 2>/dev/null
sudo systemctl restart "$SERVICE_NAME"

echo "[OK] Backend service started"

# Wait for backend to be ready
echo "Waiting for backend..."
for i in $(seq 1 30); do
  if curl -s -o /dev/null http://localhost:3000/health 2>/dev/null; then
    echo "[OK] Backend is ready"
    break
  fi
  sleep 1
done

echo ""
echo "── Installing Client ──"
echo ""

# ── Clone and build client ──

if [ -d "$INSTALL_DIR/client/.git" ]; then
  echo "Updating client..."
  cd "$INSTALL_DIR/client"
  sudo git pull
else
  echo "Cloning client..."
  sudo git clone https://github.com/Hyzokaaa/open-helpdesk-client.git "$INSTALL_DIR/client"
fi

cd "$INSTALL_DIR/client"

sudo tee "$INSTALL_DIR/client/.env" > /dev/null << EOF
VITE_API_URL=$VITE_API_URL
VITE_APP_NAME=$APP_NAME
EOF

echo "Installing dependencies..."
sudo npm install 2>&1 | tail -1
echo "Building..."
sudo npm run build 2>&1 | tail -1

# ── Deploy to nginx ──

sudo mkdir -p "$WEB_ROOT"
sudo rm -rf "$WEB_ROOT"/*
sudo cp -r "$INSTALL_DIR/client/dist/"* "$WEB_ROOT/"

echo "[OK] Client built and deployed"

# ── Configure nginx ──

echo ""
echo "── Configuring nginx ──"
echo ""

sudo tee /etc/nginx/sites-available/openhelpdesk > /dev/null << EOF
server {
    listen 80;
    server_name $SERVER_NAME;

    root $WEB_ROOT;
    index index.html;

    # Frontend (SPA)
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Cache static assets
    location /assets {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Backend API
    location /api/ {
        proxy_pass http://localhost:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
sudo ln -sf /etc/nginx/sites-available/openhelpdesk /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

echo "[OK] nginx configured"

# ── Done ──

echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║           Installation Complete!                     ║"
echo "  ╠══════════════════════════════════════════════════════╣"
echo "  ║                                                      ║"
echo "  ║  URL:    http://$SERVER_NAME"
echo "  ║  Admin:  $ADMIN_EMAIL"
echo "  ║                                                      ║"
echo "  ║  Backend config:  $INSTALL_DIR/backend/.env"
echo "  ║  Client config:   $INSTALL_DIR/client/.env"
echo "  ║  Storage:         $INSTALL_DIR/backend/data/storage"
echo "  ║  Web root:        $WEB_ROOT"
echo "  ║                                                      ║"
echo "  ║  Commands:                                           ║"
echo "  ║    sudo systemctl status $SERVICE_NAME"
echo "  ║    sudo journalctl -u $SERVICE_NAME -f"
echo "  ║                                                      ║"
echo "  ║  For HTTPS, configure SSL with certbot:              ║"
echo "  ║    sudo certbot --nginx -d $SERVER_NAME"
echo "  ║                                                      ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
