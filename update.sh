#!/bin/bash
set -e

# Open Helpdesk - Update Script
# Checks for updates, shows compatibility, and lets you choose what to update.
#
# Usage:
#   bash update.sh           # interactive — check and choose
#   bash update.sh all       # update backend + client
#   bash update.sh backend   # update backend only
#   bash update.sh client    # update client only

INSTALL_DIR="${INSTALL_DIR:-/opt/open-helpdesk}"
WEB_ROOT="${WEB_ROOT:-/var/www/openhelpdesk}"
SERVICE_NAME="${SERVICE_NAME:-openhelpdesk-backend}"

export PATH="$PATH:/usr/sbin"

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║     Open Helpdesk Updater            ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# ── Helpers ──

read_pkg_version() {
  node -p "require('$1/package.json').version" 2>/dev/null || echo "unknown"
}

read_remote_pkg_version() {
  local dir=$1
  local branch=$2
  git -C "$dir" show "origin/$branch:package.json" 2>/dev/null | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).version" 2>/dev/null || echo "unknown"
}

read_remote_compatibility() {
  local dir=$1
  local branch=$2
  git -C "$dir" show "origin/$branch:package.json" 2>/dev/null | node -p "
    const pkg = JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8'));
    pkg.compatibility && pkg.compatibility.backend ? pkg.compatibility.backend : '';
  " 2>/dev/null || echo ""
}

version_satisfies() {
  local version=$1
  local range=$2
  node -e "
    const [, minOp, minVer] = '$range'.match(/^(>=?)(\d+\.\d+\.\d+)/) || [];
    const [, , maxVer] = '$range'.match(/<(\d+\.\d+\.\d+)/) || [];
    const v = '$version'.split('.').map(Number);
    const min = (minVer || '0.0.0').split('.').map(Number);
    const max = (maxVer || '999.999.999').split('.').map(Number);
    const gte = (a, b) => a[0] > b[0] || (a[0] === b[0] && (a[1] > b[1] || (a[1] === b[1] && a[2] >= b[2])));
    const lt = (a, b) => a[0] < b[0] || (a[0] === b[0] && (a[1] < b[1] || (a[1] === b[1] && a[2] < b[2])));
    const ok = gte(v, min) && lt(v, max);
    process.exit(ok ? 0 : 1);
  " 2>/dev/null
}

# ── Validate repos ──

BACKEND_DIR="$INSTALL_DIR/backend"
CLIENT_DIR="$INSTALL_DIR/client"

HAS_BACKEND=false
HAS_CLIENT=false

[ -d "$BACKEND_DIR/.git" ] && HAS_BACKEND=true
[ -d "$CLIENT_DIR/.git" ] && HAS_CLIENT=true

if [ "$HAS_BACKEND" = "false" ] && [ "$HAS_CLIENT" = "false" ]; then
  echo "  [ERROR] No repos found at $INSTALL_DIR"
  echo "  Expected: $BACKEND_DIR and/or $CLIENT_DIR"
  exit 1
fi

# ── Fetch latest ──

echo "── Checking for updates ──"
echo ""

if [ "$HAS_BACKEND" = "true" ]; then
  git -C "$BACKEND_DIR" config --global --add safe.directory "$BACKEND_DIR" 2>/dev/null || true
  BACKEND_BRANCH=$(git -C "$BACKEND_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  sudo git -C "$BACKEND_DIR" fetch origin --quiet &>/dev/null
fi

if [ "$HAS_CLIENT" = "true" ]; then
  git -C "$CLIENT_DIR" config --global --add safe.directory "$CLIENT_DIR" 2>/dev/null || true
  CLIENT_BRANCH=$(git -C "$CLIENT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  sudo git -C "$CLIENT_DIR" fetch origin --quiet &>/dev/null
fi

# ── Read versions ──

BACKEND_UPDATE=false
CLIENT_UPDATE=false

if [ "$HAS_BACKEND" = "true" ]; then
  BACKEND_CURRENT=$(read_pkg_version "$BACKEND_DIR")
  BACKEND_LATEST=$(read_remote_pkg_version "$BACKEND_DIR" "$BACKEND_BRANCH")
  BACKEND_CURRENT_COMMIT=$(git -C "$BACKEND_DIR" rev-parse --short HEAD 2>/dev/null)
  BACKEND_LATEST_COMMIT=$(git -C "$BACKEND_DIR" rev-parse --short "origin/$BACKEND_BRANCH" 2>/dev/null)

  if [ "$BACKEND_CURRENT_COMMIT" != "$BACKEND_LATEST_COMMIT" ]; then
    BACKEND_UPDATE=true
  fi
fi

if [ "$HAS_CLIENT" = "true" ]; then
  CLIENT_CURRENT=$(read_pkg_version "$CLIENT_DIR")
  CLIENT_LATEST=$(read_remote_pkg_version "$CLIENT_DIR" "$CLIENT_BRANCH")
  CLIENT_CURRENT_COMMIT=$(git -C "$CLIENT_DIR" rev-parse --short HEAD 2>/dev/null)
  CLIENT_LATEST_COMMIT=$(git -C "$CLIENT_DIR" rev-parse --short "origin/$CLIENT_BRANCH" 2>/dev/null)
  CLIENT_COMPAT=$(read_remote_compatibility "$CLIENT_DIR" "$CLIENT_BRANCH")

  if [ "$CLIENT_CURRENT_COMMIT" != "$CLIENT_LATEST_COMMIT" ]; then
    CLIENT_UPDATE=true
  fi
fi

# ── Display status ──

if [ "$HAS_BACKEND" = "true" ]; then
  if [ "$BACKEND_UPDATE" = "true" ]; then
    echo "  Backend:   v$BACKEND_CURRENT → v$BACKEND_LATEST  (update available)"
    CHANGES=$(git -C "$BACKEND_DIR" log --oneline "$BACKEND_CURRENT_COMMIT..$BACKEND_LATEST_COMMIT" 2>/dev/null || true)
    if [ -n "$CHANGES" ]; then
      CHANGE_COUNT=$(echo "$CHANGES" | wc -l)
      echo "             $CHANGE_COUNT new commit(s)"
    fi
  else
    echo "  Backend:   v$BACKEND_CURRENT  (up to date)"
  fi
fi

if [ "$HAS_CLIENT" = "true" ]; then
  if [ "$CLIENT_UPDATE" = "true" ]; then
    echo "  Client:    v$CLIENT_CURRENT → v$CLIENT_LATEST  (update available)"
    CHANGES=$(git -C "$CLIENT_DIR" log --oneline "$CLIENT_CURRENT_COMMIT..$CLIENT_LATEST_COMMIT" 2>/dev/null || true)
    if [ -n "$CHANGES" ]; then
      CHANGE_COUNT=$(echo "$CHANGES" | wc -l)
      echo "             $CHANGE_COUNT new commit(s)"
    fi
  else
    echo "  Client:    v$CLIENT_CURRENT  (up to date)"
  fi
fi

echo ""

# ── Nothing to update? ──

if [ "$BACKEND_UPDATE" = "false" ] && [ "$CLIENT_UPDATE" = "false" ]; then
  echo "  Everything is up to date!"
  echo ""
  exit 0
fi

# ── Compatibility check ──

COMPAT_WARN=""

if [ "$CLIENT_UPDATE" = "true" ] && [ -n "$CLIENT_COMPAT" ]; then
  # Check if current backend satisfies the new client's requirement
  BACKEND_TO_CHECK="$BACKEND_CURRENT"
  if [ "$BACKEND_UPDATE" = "true" ]; then
    BACKEND_TO_CHECK="$BACKEND_LATEST"
  fi

  if ! version_satisfies "$BACKEND_TO_CHECK" "$CLIENT_COMPAT"; then
    COMPAT_WARN="  [!] Client v$CLIENT_LATEST requires backend $CLIENT_COMPAT"
    if [ "$BACKEND_UPDATE" = "false" ]; then
      COMPAT_WARN="$COMPAT_WARN
  [!] Your backend is v$BACKEND_CURRENT — update backend first!"
    else
      COMPAT_WARN="$COMPAT_WARN
  [!] Backend v$BACKEND_LATEST satisfies this — update backend before or together with client"
    fi
  fi
fi

# Check: updating only client when backend needs update too
if [ "$CLIENT_UPDATE" = "true" ] && [ "$BACKEND_UPDATE" = "true" ] && [ -n "$CLIENT_COMPAT" ]; then
  if ! version_satisfies "$BACKEND_CURRENT" "$CLIENT_COMPAT"; then
    COMPAT_BLOCK_CLIENT=true
  fi
fi

if [ -n "$COMPAT_WARN" ]; then
  echo "$COMPAT_WARN"
  echo ""
fi

# ── Choose what to update ──

UPDATE_BACKEND=false
UPDATE_CLIENT=false

MODE="${1}"

if [ -z "$MODE" ]; then
  echo "  What would you like to update?"
  echo ""
  if [ "$BACKEND_UPDATE" = "true" ] && [ "$CLIENT_UPDATE" = "true" ]; then
    echo "    1) All (backend + client)"
    echo "    2) Backend only"
    echo "    3) Client only"
    echo "    0) Cancel"
    echo ""
    read -p "  Choose [1]: " CHOICE
    CHOICE="${CHOICE:-1}"
    case "$CHOICE" in
      1) UPDATE_BACKEND=true; UPDATE_CLIENT=true ;;
      2) UPDATE_BACKEND=true ;;
      3) UPDATE_CLIENT=true ;;
      0) echo "  Cancelled."; exit 0 ;;
      *) echo "  Invalid choice."; exit 1 ;;
    esac
  elif [ "$BACKEND_UPDATE" = "true" ]; then
    read -p "  Update backend to v$BACKEND_LATEST? (Y/n): " CONFIRM
    [ "${CONFIRM,,}" != "n" ] && UPDATE_BACKEND=true || exit 0
  elif [ "$CLIENT_UPDATE" = "true" ]; then
    read -p "  Update client to v$CLIENT_LATEST? (Y/n): " CONFIRM
    [ "${CONFIRM,,}" != "n" ] && UPDATE_CLIENT=true || exit 0
  fi
else
  case "$MODE" in
    all)     UPDATE_BACKEND=true; UPDATE_CLIENT=true ;;
    backend) UPDATE_BACKEND=true ;;
    client)  UPDATE_CLIENT=true ;;
    *)       echo "  Usage: bash update.sh [all|backend|client]"; exit 1 ;;
  esac
fi

# ── Block incompatible updates ──

if [ "$UPDATE_CLIENT" = "true" ] && [ "$UPDATE_BACKEND" = "false" ] && [ "${COMPAT_BLOCK_CLIENT:-false}" = "true" ]; then
  echo ""
  echo "  [ERROR] Cannot update client alone."
  echo "  Client v$CLIENT_LATEST requires backend $CLIENT_COMPAT"
  echo "  Your backend is v$BACKEND_CURRENT — update backend first or choose 'all'."
  echo ""
  exit 1
fi

echo ""

# ── Update backend ──

if [ "$UPDATE_BACKEND" = "true" ] && [ "$HAS_BACKEND" = "true" ]; then
  echo "── Updating Backend (v$BACKEND_CURRENT → v$BACKEND_LATEST) ──"
  cd "$BACKEND_DIR"
  sudo git pull
  echo "Installing dependencies..."
  sudo npm install --production=false 2>&1 | tail -1
  echo "Building..."
  sudo npm run build 2>&1 | tail -1
  sudo systemctl restart "$SERVICE_NAME"
  echo "[OK] Backend updated to v$BACKEND_LATEST"
  echo ""
fi

# ── Update client ──

if [ "$UPDATE_CLIENT" = "true" ] && [ "$HAS_CLIENT" = "true" ]; then
  echo "── Updating Client (v$CLIENT_CURRENT → v$CLIENT_LATEST) ──"
  cd "$CLIENT_DIR"
  sudo git pull
  echo "Installing dependencies..."
  sudo npm install 2>&1 | tail -1
  echo "Building..."
  sudo npm run build 2>&1 | tail -1
  sudo rm -rf "$WEB_ROOT"/*
  sudo cp -r "$CLIENT_DIR/dist/"* "$WEB_ROOT/"
  echo "[OK] Client updated to v$CLIENT_LATEST"
  echo ""
fi

# ── Summary ──

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║        Update Complete!              ║"
if [ "$UPDATE_BACKEND" = "true" ]; then
echo "  ║  Backend:  v$BACKEND_LATEST"
fi
if [ "$UPDATE_CLIENT" = "true" ]; then
echo "  ║  Client:   v$CLIENT_LATEST"
fi
echo "  ╚══════════════════════════════════════╝"
echo ""
