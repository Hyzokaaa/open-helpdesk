#!/bin/bash
set -e

# Open Helpdesk - Full Update Script
# Updates backend + client in one command.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Hyzokaaa/open-helpdesk/main/update.sh -o update.sh
#   bash update.sh

INSTALL_DIR="${INSTALL_DIR:-/opt/open-helpdesk}"
WEB_ROOT="${WEB_ROOT:-/var/www/openhelpdesk}"
SERVICE_NAME="${SERVICE_NAME:-openhelpdesk-backend}"

export PATH="$PATH:/usr/sbin"

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║     Open Helpdesk Updater            ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# ── Backend ──

if [ -d "$INSTALL_DIR/backend/.git" ]; then
  echo "── Updating Backend ──"
  cd "$INSTALL_DIR/backend"
  git config --global --add safe.directory "$INSTALL_DIR/backend" 2>/dev/null || true
  sudo git pull
  echo "Installing dependencies..."
  sudo npm install --production=false 2>&1 | tail -1
  echo "Building..."
  sudo npm run build 2>&1 | tail -1
  sudo systemctl restart "$SERVICE_NAME"
  echo "[OK] Backend updated"
else
  echo "[SKIP] Backend not found at $INSTALL_DIR/backend"
fi

echo ""

# ── Client ──

if [ -d "$INSTALL_DIR/client/.git" ]; then
  echo "── Updating Client ──"
  cd "$INSTALL_DIR/client"
  git config --global --add safe.directory "$INSTALL_DIR/client" 2>/dev/null || true
  sudo git pull
  echo "Installing dependencies..."
  sudo npm install 2>&1 | tail -1
  echo "Building..."
  sudo npm run build 2>&1 | tail -1
  sudo rm -rf "$WEB_ROOT"/*
  sudo cp -r "$INSTALL_DIR/client/dist/"* "$WEB_ROOT/"
  echo "[OK] Client updated"
else
  echo "[SKIP] Client not found at $INSTALL_DIR/client"
fi

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║        Update Complete!              ║"
echo "  ╚══════════════════════════════════════╝"
echo ""
