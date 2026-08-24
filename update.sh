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

# ── Version check ──

if [ -d "$INSTALL_DIR/backend/.git" ]; then
  cd "$INSTALL_DIR/backend"
  git config --global --add safe.directory "$INSTALL_DIR/backend" 2>/dev/null || true

  CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null)
  CURRENT_VERSION=$(node -e "try{const c=require('./src/changelog/changelog.data');console.log(c.coreChangelog[0].version)}catch{console.log('unknown')}" 2>/dev/null || echo "unknown")

  sudo git fetch origin &>/dev/null
  LATEST_COMMIT=$(git rev-parse --short origin/main 2>/dev/null)
  LATEST_VERSION=$(git show origin/main:src/changelog/changelog.data.ts 2>/dev/null | node -e "
    let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
      const m=d.match(/version:\s*'([^']+)'/);console.log(m?m[1]:'unknown')
    })" 2>/dev/null || echo "unknown")

  echo "  Current:   v$CURRENT_VERSION ($CURRENT_COMMIT)"
  echo "  Available: v$LATEST_VERSION ($LATEST_COMMIT)"
  echo ""

  if [ "$CURRENT_COMMIT" = "$LATEST_COMMIT" ]; then
    echo "  Already up to date!"
    echo ""
    exit 0
  fi

  CHANGES=$(git log --oneline "$CURRENT_COMMIT..origin/main" 2>/dev/null)
  if [ -n "$CHANGES" ]; then
    CHANGE_COUNT=$(echo "$CHANGES" | wc -l)
    echo "  $CHANGE_COUNT new commit(s):"
    echo "$CHANGES" | head -10 | sed 's/^/    /'
    if [ "$CHANGE_COUNT" -gt 10 ]; then
      echo "    ... and $((CHANGE_COUNT - 10)) more"
    fi
    echo ""
  fi

  read -p "  Update to v$LATEST_VERSION? (Y/n): " CONFIRM
  if [ "${CONFIRM,,}" = "n" ]; then
    echo "  Update cancelled."
    exit 0
  fi
  echo ""
fi

# ── Backend ──

if [ -d "$INSTALL_DIR/backend/.git" ]; then
  echo "── Updating Backend ──"
  cd "$INSTALL_DIR/backend"
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

# ── Done ──

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║        Update Complete!              ║"
echo "  ║  Version: v$LATEST_VERSION"
echo "  ╚══════════════════════════════════════╝"
echo ""
