#!/bin/bash
set -e

# Open Helpdesk - Full Installation Script
# Installs backend + client on a single server with PostgreSQL and nginx.
# Requirements: Node.js 22+, PostgreSQL 15+, nginx.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Hyzokaaa/open-helpdesk/main/install.sh -o install.sh
#   bash install.sh
#
# Custom install (e.g. second instance on same server):
#   INSTALL_DIR=/opt/oh-test BACKEND_PORT=3001 NGINX_PORT=8080 \
#     SERVICE_NAME=oh-test DB_NAME=oh_test bash install.sh

# Detect if running via pipe (curl | bash) — read won't work
if [ ! -t 0 ]; then
  echo "[ERROR] This script requires interactive input."
  echo ""
  echo "  Download first, then run:"
  echo "    curl -fsSL https://raw.githubusercontent.com/Hyzokaaa/open-helpdesk/main/install.sh -o install.sh"
  echo "    bash install.sh"
  echo ""
  exit 1
fi

INSTALL_DIR="${INSTALL_DIR:-/opt/open-helpdesk}"
WEB_ROOT="${WEB_ROOT:-/var/www/openhelpdesk}"
SERVICE_USER="${SERVICE_USER:-openhelpdesk}"
SERVICE_NAME="${SERVICE_NAME:-openhelpdesk-backend}"
BACKEND_PORT="${BACKEND_PORT:-3000}"
NGINX_PORT="${NGINX_PORT:-80}"
NGINX_SITE="${NGINX_SITE:-openhelpdesk}"

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║     Open Helpdesk Installer          ║"
echo "  ╚══════════════════════════════════════╝"
echo ""
echo "  Install dir:    $INSTALL_DIR"
echo "  Backend port:   $BACKEND_PORT"
echo "  Nginx port:     $NGINX_PORT"
echo "  Service name:   $SERVICE_NAME"
echo ""

# ══════════════════════════════════════════════
# Step 1/6 — Prerequisites
# ══════════════════════════════════════════════

echo "── Step 1/6: Checking prerequisites ──"
echo ""

# Node.js
if ! command -v node &> /dev/null; then
  read -p "[MISSING] Node.js is not installed. Install it now? (Y/n): " INSTALL_NODE
  if [ "${INSTALL_NODE,,}" != "n" ]; then
    echo "Installing Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
  else
    echo "[ERROR] Node.js is required. Aborting."
    exit 1
  fi
else
  NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
  if [ "$NODE_VERSION" -lt 22 ]; then
    echo "[ERROR] Node.js 22+ required. Found: $(node -v)"
    exit 1
  fi
fi
echo "[OK] Node.js $(node -v)"

# PostgreSQL
if ! command -v psql &> /dev/null; then
  read -p "[MISSING] PostgreSQL is not installed. Install it now? (Y/n): " INSTALL_PG
  if [ "${INSTALL_PG,,}" != "n" ]; then
    echo "Installing PostgreSQL..."
    sudo apt-get install -y postgresql
  else
    echo "[ERROR] PostgreSQL is required. Aborting."
    exit 1
  fi
fi
echo "[OK] PostgreSQL found"

# nginx
if ! command -v nginx &> /dev/null && ! [ -x /usr/sbin/nginx ]; then
  read -p "[MISSING] nginx is not installed. Install it now? (Y/n): " INSTALL_NGINX
  if [ "${INSTALL_NGINX,,}" != "n" ]; then
    echo "Installing nginx..."
    sudo apt-get install -y nginx
  else
    echo "[ERROR] nginx is required. Aborting."
    exit 1
  fi
fi
export PATH="$PATH:/usr/sbin"
echo "[OK] nginx found"

echo ""

# ══════════════════════════════════════════════
# Step 2/6 — Configuration
# ══════════════════════════════════════════════

echo "── Step 2/6: Configuration ──"
echo ""

read -p "Server hostname (e.g. helpdesk.yourcompany.com): " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-localhost}

echo ""
echo "  Database"
echo ""

read -p "  Host [localhost]: " DB_HOST
DB_HOST=${DB_HOST:-localhost}

read -p "  Port [5432]: " DB_PORT
DB_PORT=${DB_PORT:-5432}

read -p "  Name [${DB_NAME:-open_helpdesk}]: " DB_NAME_INPUT
DB_NAME=${DB_NAME_INPUT:-${DB_NAME:-open_helpdesk}}

read -p "  User [postgres]: " DB_USER
DB_USER=${DB_USER:-postgres}

DB_PASSWORD_DEFAULT=$(openssl rand -hex 16)
read -sp "  Password [$DB_PASSWORD_DEFAULT]: " DB_PASSWORD_INPUT
echo ""
DB_PASSWORD=${DB_PASSWORD_INPUT:-$DB_PASSWORD_DEFAULT}

echo ""
echo "  Application"
echo ""

read -p "  Admin email [admin@${SERVER_NAME}]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@${SERVER_NAME}}

read -sp "  Admin password [admin1234]: " ADMIN_PASSWORD
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin1234}
echo ""

read -p "  App name [Open Helpdesk]: " APP_NAME
APP_NAME=${APP_NAME:-Open Helpdesk}

JWT_SECRET=$(openssl rand -hex 32)

# Determine URLs based on hostname
if [ "$SERVER_NAME" = "localhost" ]; then
  if [ "$NGINX_PORT" = "80" ]; then
    FRONTEND_URL="http://localhost"
    VITE_API_URL="http://localhost/api"
  else
    FRONTEND_URL="http://localhost:$NGINX_PORT"
    VITE_API_URL="http://localhost:$NGINX_PORT/api"
  fi
else
  FRONTEND_URL="https://$SERVER_NAME"
  VITE_API_URL="https://$SERVER_NAME/api"
fi

echo ""

# ══════════════════════════════════════════════
# Step 3/6 — Database setup
# ══════════════════════════════════════════════

echo "── Step 3/6: Database setup ──"
echo ""

# Ensure PostgreSQL is running
sudo systemctl start postgresql 2>/dev/null || true

# Create database if it doesn't exist
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
  echo "[OK] Database '$DB_NAME' already exists"
else
  read -p "Database '$DB_NAME' does not exist. Create it? (Y/n): " CREATE_DB
  if [ "${CREATE_DB,,}" != "n" ]; then
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null
    echo "[OK] Database '$DB_NAME' created"
  else
    echo "[WARN] Skipped. Make sure the database exists before starting."
  fi
fi

# Configure user password
if [ -n "$DB_PASSWORD" ]; then
  read -p "Set password for database user '$DB_USER'? (Y/n): " SET_DB_PASS
  if [ "${SET_DB_PASS,,}" != "n" ]; then
    sudo -u postgres psql -c "ALTER USER $DB_USER PASSWORD '$DB_PASSWORD';" 2>/dev/null
    echo "[OK] Password set for '$DB_USER'"

    # Ensure password auth works for local TCP connections
    PG_HBA=$(sudo -u postgres psql -t -c "SHOW hba_file;" 2>/dev/null | tr -d ' ')
    if [ -n "$PG_HBA" ] && grep -q "127.0.0.1/32.*peer" "$PG_HBA" 2>/dev/null; then
      sudo sed -i 's/127.0.0.1\/32.*peer/127.0.0.1\/32            scram-sha-256/' "$PG_HBA"
      sudo systemctl reload postgresql
    fi
  fi
fi

echo ""

# ══════════════════════════════════════════════
# Step 4/6 — Backend
# ══════════════════════════════════════════════

echo "── Step 4/6: Installing backend ──"
echo ""

# Create system user
if ! id "$SERVICE_USER" &> /dev/null; then
  sudo useradd --system --no-create-home --shell /bin/false "$SERVICE_USER" 2>/dev/null || true
fi

# Clone and build
sudo mkdir -p "$INSTALL_DIR"

if [ -d "$INSTALL_DIR/backend/.git" ]; then
  echo "Updating backend..."
  git config --global --add safe.directory "$INSTALL_DIR/backend" 2>/dev/null || true
  cd "$INSTALL_DIR/backend"
  sudo git pull
else
  echo "Cloning backend..."
  sudo git clone https://github.com/Hyzokaaa/open-helpdesk-backend.git "$INSTALL_DIR/backend"
  git config --global --add safe.directory "$INSTALL_DIR/backend" 2>/dev/null || true
fi

cd "$INSTALL_DIR/backend"
echo "Installing dependencies..."
sudo npm install --production=false 2>&1 | tail -1
echo "Building..."
sudo npm run build 2>&1 | tail -1

# Create .env
sudo mkdir -p "$INSTALL_DIR/backend/data/storage"

if [ ! -f "$INSTALL_DIR/backend/.env" ]; then
  sudo tee "$INSTALL_DIR/backend/.env" > /dev/null << EOF
PORT=$BACKEND_PORT
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

# Create systemd service
sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null << EOF
[Unit]
Description=Open Helpdesk Backend ($SERVICE_NAME)
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
  if curl -s -o /dev/null http://localhost:$BACKEND_PORT/health 2>/dev/null; then
    echo "[OK] Backend is ready"
    break
  fi
  sleep 1
done

echo ""

# ══════════════════════════════════════════════
# Step 5/6 — Client
# ══════════════════════════════════════════════

echo "── Step 5/6: Installing client ──"
echo ""

if [ -d "$INSTALL_DIR/client/.git" ]; then
  echo "Updating client..."
  git config --global --add safe.directory "$INSTALL_DIR/client" 2>/dev/null || true
  cd "$INSTALL_DIR/client"
  sudo git pull
else
  echo "Cloning client..."
  sudo git clone https://github.com/Hyzokaaa/open-helpdesk-client.git "$INSTALL_DIR/client"
  git config --global --add safe.directory "$INSTALL_DIR/client" 2>/dev/null || true
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

# Deploy to web root
sudo mkdir -p "$WEB_ROOT"
sudo rm -rf "$WEB_ROOT"/*
sudo cp -r "$INSTALL_DIR/client/dist/"* "$WEB_ROOT/"

echo "[OK] Client built and deployed"
echo ""

# ══════════════════════════════════════════════
# Step 6/6 — nginx
# ══════════════════════════════════════════════

echo "── Step 6/6: Configuring nginx ──"
echo ""

# Detect nginx config structure
if [ -d /etc/nginx/sites-available ]; then
  NGINX_CONF_PATH="/etc/nginx/sites-available/$NGINX_SITE.conf"
  NGINX_LINK_PATH="/etc/nginx/sites-enabled/$NGINX_SITE.conf"
elif [ -d /etc/nginx/conf.d ]; then
  NGINX_CONF_PATH="/etc/nginx/conf.d/$NGINX_SITE.conf"
  NGINX_LINK_PATH=""
else
  echo "[ERROR] Could not detect nginx config directory"
  exit 1
fi

sudo tee "$NGINX_CONF_PATH" > /dev/null << EOF
server {
    listen $NGINX_PORT;
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
        proxy_pass http://localhost:$BACKEND_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

if [ -n "$NGINX_LINK_PATH" ]; then
  sudo ln -sf "$NGINX_CONF_PATH" "$NGINX_LINK_PATH"
fi
sudo nginx -t && sudo systemctl restart nginx

echo "[OK] nginx configured"

# ══════════════════════════════════════════════
# Done
# ══════════════════════════════════════════════

echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║           Installation Complete!                     ║"
echo "  ╠══════════════════════════════════════════════════════╣"
echo "  ║                                                      ║"
echo "  ║  URL:      $FRONTEND_URL"
echo "  ║  Admin:    $ADMIN_EMAIL"
echo "  ║                                                      ║"
echo "  ║  Backend:  $INSTALL_DIR/backend/.env"
echo "  ║  Client:   $INSTALL_DIR/client/.env"
echo "  ║  Storage:  $INSTALL_DIR/backend/data/storage"
echo "  ║  Web root: $WEB_ROOT"
echo "  ║                                                      ║"
echo "  ║  Commands:                                           ║"
echo "  ║    sudo systemctl status $SERVICE_NAME"
echo "  ║    sudo journalctl -u $SERVICE_NAME -f"
echo "  ║                                                      ║"
echo "  ║  For HTTPS:                                          ║"
echo "  ║    sudo certbot --nginx -d $SERVER_NAME"
echo "  ║                                                      ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
