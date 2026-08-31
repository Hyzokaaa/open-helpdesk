#!/bin/bash
set -e

# Open Helpdesk - Update Script
# Checks for updates against stable releases and lets you choose how to update.
#
# Usage:
#   bash update.sh                      # interactive (recommended)
#   bash update.sh --release            # update to latest stable release
#   bash update.sh --branch main        # update to latest commit on a branch
#   bash update.sh --branch dev         # update to latest commit on dev
#   bash update.sh --version 1.21.0     # update to a specific product version

INSTALL_DIR="${INSTALL_DIR:-/opt/open-helpdesk}"
WEB_ROOT="${WEB_ROOT:-/var/www/openhelpdesk}"
SERVICE_NAME="${SERVICE_NAME:-openhelpdesk-backend}"
GITHUB_UMBRELLA="Hyzokaaa/open-helpdesk"

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

read_remote_compatibility() {
  local dir=$1
  local ref=$2
  git -C "$dir" show "$ref:package.json" 2>/dev/null | node -p "
    const pkg = JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8'));
    pkg.compatibility && pkg.compatibility.backend ? pkg.compatibility.backend : '';
  " 2>/dev/null || echo ""
}

version_satisfies() {
  local version=$1
  local range=$2
  node -e "
    const [, , minVer] = '$range'.match(/^(>=?)(\d+\.\d+\.\d+)/) || [];
    const [, , maxVer] = '$range'.match(/<(\d+\.\d+\.\d+)/) || [];
    const v = '$version'.split('.').map(Number);
    const min = (minVer || '0.0.0').split('.').map(Number);
    const max = (maxVer || '999.999.999').split('.').map(Number);
    const gte = (a, b) => a[0] > b[0] || (a[0] === b[0] && (a[1] > b[1] || (a[1] === b[1] && a[2] >= b[2])));
    const lt = (a, b) => a[0] < b[0] || (a[0] === b[0] && (a[1] < b[1] || (a[1] === b[1] && a[2] < b[2])));
    process.exit(gte(v, min) && lt(v, max) ? 0 : 1);
  " 2>/dev/null
}

compare_versions() {
  node -e "
    const a = '$1'.split('.').map(Number);
    const b = '$2'.split('.').map(Number);
    for (let i = 0; i < 3; i++) {
      if ((a[i]||0) < (b[i]||0)) { process.stdout.write('lt'); process.exit(); }
      if ((a[i]||0) > (b[i]||0)) { process.stdout.write('gt'); process.exit(); }
    }
    process.stdout.write('eq');
  " 2>/dev/null
}

fetch_latest_release() {
  local json
  json=$(curl -sf -H "Accept: application/vnd.github.v3+json" -H "User-Agent: OpenHelpdesk" \
    "https://api.github.com/repos/$GITHUB_UMBRELLA/releases/latest" 2>/dev/null) || return 1

  RELEASE_PRODUCT=$(echo "$json" | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).tag_name.replace(/^v/,'')" 2>/dev/null)
  RELEASE_URL=$(echo "$json" | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).html_url" 2>/dev/null)
  local body
  body=$(echo "$json" | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).body" 2>/dev/null)
  RELEASE_BACKEND=$(echo "$body" | grep -oi 'backend:\s*v\?[0-9.]*' | grep -o '[0-9][0-9.]*' | head -1)
  RELEASE_CLIENT=$(echo "$body" | grep -oi 'client:\s*v\?[0-9.]*' | grep -o '[0-9][0-9.]*' | head -1)
}

fetch_release_by_version() {
  local version=$1
  local json
  json=$(curl -sf -H "Accept: application/vnd.github.v3+json" -H "User-Agent: OpenHelpdesk" \
    "https://api.github.com/repos/$GITHUB_UMBRELLA/releases/tags/v$version" 2>/dev/null) || return 1

  RELEASE_PRODUCT="$version"
  RELEASE_URL=$(echo "$json" | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).html_url" 2>/dev/null)
  local body
  body=$(echo "$json" | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).body" 2>/dev/null)
  RELEASE_BACKEND=$(echo "$body" | grep -oi 'backend:\s*v\?[0-9.]*' | grep -o '[0-9][0-9.]*' | head -1)
  RELEASE_CLIENT=$(echo "$body" | grep -oi 'client:\s*v\?[0-9.]*' | grep -o '[0-9][0-9.]*' | head -1)
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

# ── Read current versions ──

if [ "$HAS_BACKEND" = "true" ]; then
  git -C "$BACKEND_DIR" config --global --add safe.directory "$BACKEND_DIR" 2>/dev/null || true
  BACKEND_CURRENT=$(read_pkg_version "$BACKEND_DIR")
fi

if [ "$HAS_CLIENT" = "true" ]; then
  git -C "$CLIENT_DIR" config --global --add safe.directory "$CLIENT_DIR" 2>/dev/null || true
  CLIENT_CURRENT=$(read_pkg_version "$CLIENT_DIR")
fi

echo "  Current:"
[ "$HAS_BACKEND" = "true" ] && echo "    Backend:   v$BACKEND_CURRENT"
[ "$HAS_CLIENT" = "true" ] && echo "    Client:    v$CLIENT_CURRENT"
echo ""

# ── Fetch latest release from GitHub ──

echo "  Checking for updates..."
echo ""

RELEASE_PRODUCT=""
RELEASE_BACKEND=""
RELEASE_CLIENT=""
RELEASE_URL=""

if fetch_latest_release; then
  BACKEND_VS_RELEASE=$(compare_versions "$BACKEND_CURRENT" "$RELEASE_BACKEND")
  CLIENT_VS_RELEASE=$(compare_versions "$CLIENT_CURRENT" "$RELEASE_CLIENT")

  if [ "$BACKEND_VS_RELEASE" = "lt" ] || [ "$CLIENT_VS_RELEASE" = "lt" ]; then
    echo "  Latest stable release: Open Helpdesk v$RELEASE_PRODUCT (update available)"
  else
    echo "  Latest stable release: Open Helpdesk v$RELEASE_PRODUCT (up to date)"
  fi
  echo "    Backend:   v$RELEASE_BACKEND"
  echo "    Client:    v$RELEASE_CLIENT"
else
  echo "  [!] Could not fetch release info from GitHub."
  echo "      You can still update from a branch."
fi
echo ""

# ── Fetch latest branch info ──

if [ "$HAS_BACKEND" = "true" ]; then
  sudo git -C "$BACKEND_DIR" fetch origin --tags --quiet &>/dev/null || true
fi
if [ "$HAS_CLIENT" = "true" ]; then
  sudo git -C "$CLIENT_DIR" fetch origin --tags --quiet &>/dev/null || true
fi

# ── Parse CLI arguments ──

MODE=""
ARG_BRANCH=""
ARG_VERSION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --release)  MODE="release"; shift ;;
    --branch)   MODE="branch"; ARG_BRANCH="${2}"; shift 2 ;;
    --version)  MODE="version"; ARG_VERSION="${2}"; shift 2 ;;
    *)          echo "  Usage: bash update.sh [--release | --branch <name> | --version <x.y.z>]"; exit 1 ;;
  esac
done

# ── Interactive mode ──

if [ -z "$MODE" ]; then
  echo "  What would you like to do?"
  echo ""
  echo "    1) Update to latest stable release (v${RELEASE_PRODUCT:-?}) — recommended"
  echo "    2) Update to latest branch commit (advanced)"
  echo "    3) Update to a specific product version"
  echo "    0) Cancel"
  echo ""
  read -p "  Choose [1]: " CHOICE
  CHOICE="${CHOICE:-1}"

  case "$CHOICE" in
    1) MODE="release" ;;
    2)
      MODE="branch"
      echo ""
      echo "    Available branches:"
      echo "      a) main — stable, between releases"
      echo "      b) dev  — bleeding edge"
      echo ""
      read -p "    Choose branch [main]: " BR_CHOICE
      case "${BR_CHOICE:-a}" in
        a|main) ARG_BRANCH="main" ;;
        b|dev)  ARG_BRANCH="dev" ;;
        *)      ARG_BRANCH="$BR_CHOICE" ;;
      esac
      ;;
    3)
      MODE="version"
      read -p "  Enter product version (e.g. 1.21.0): " ARG_VERSION
      ;;
    0) echo "  Cancelled."; exit 0 ;;
    *) echo "  Invalid choice."; exit 1 ;;
  esac
fi

echo ""

# ── Resolve target versions ──

TARGET_BACKEND=""
TARGET_CLIENT=""
UPDATE_METHOD="" # "tag" or "branch"

case "$MODE" in
  release)
    if [ -z "$RELEASE_PRODUCT" ]; then
      echo "  [ERROR] No release info available. Cannot update to stable release."
      exit 1
    fi
    TARGET_BACKEND="$RELEASE_BACKEND"
    TARGET_CLIENT="$RELEASE_CLIENT"
    UPDATE_METHOD="tag"
    echo "  Updating to Open Helpdesk v$RELEASE_PRODUCT"
    echo "    Backend:   v$BACKEND_CURRENT → v$TARGET_BACKEND"
    echo "    Client:    v$CLIENT_CURRENT → v$TARGET_CLIENT"
    ;;
  version)
    if [ -z "$ARG_VERSION" ]; then
      echo "  [ERROR] No version specified."; exit 1
    fi
    echo "  Fetching release v$ARG_VERSION..."
    if ! fetch_release_by_version "$ARG_VERSION"; then
      echo "  [ERROR] Release v$ARG_VERSION not found on GitHub."; exit 1
    fi
    TARGET_BACKEND="$RELEASE_BACKEND"
    TARGET_CLIENT="$RELEASE_CLIENT"
    UPDATE_METHOD="tag"
    echo "  Updating to Open Helpdesk v$ARG_VERSION"
    echo "    Backend:   v$BACKEND_CURRENT → v$TARGET_BACKEND"
    echo "    Client:    v$CLIENT_CURRENT → v$TARGET_CLIENT"
    ;;
  branch)
    if [ -z "$ARG_BRANCH" ]; then
      echo "  [ERROR] No branch specified."; exit 1
    fi
    UPDATE_METHOD="branch"
    echo "  Updating to latest commit on branch '$ARG_BRANCH'"

    BRANCH_HAS_CHANGES=false

    if [ "$HAS_BACKEND" = "true" ]; then
      BACKEND_BRANCH_VERSION=$(git -C "$BACKEND_DIR" show "origin/$ARG_BRANCH:package.json" 2>/dev/null | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).version" 2>/dev/null || echo "unknown")
      BACKEND_LOCAL_COMMIT=$(git -C "$BACKEND_DIR" rev-parse --short HEAD 2>/dev/null)
      BACKEND_REMOTE_COMMIT=$(git -C "$BACKEND_DIR" rev-parse --short "origin/$ARG_BRANCH" 2>/dev/null || echo "unknown")
      if [ "$BACKEND_LOCAL_COMMIT" != "$BACKEND_REMOTE_COMMIT" ]; then
        BACKEND_COMMIT_COUNT=$(git -C "$BACKEND_DIR" log --oneline "$BACKEND_LOCAL_COMMIT..$BACKEND_REMOTE_COMMIT" 2>/dev/null | wc -l | tr -d ' ')
        echo "    Backend:   v$BACKEND_CURRENT → v$BACKEND_BRANCH_VERSION  ($BACKEND_COMMIT_COUNT new commit(s))"
        BRANCH_HAS_CHANGES=true
      else
        echo "    Backend:   v$BACKEND_CURRENT  (up to date)"
      fi
    fi

    if [ "$HAS_CLIENT" = "true" ]; then
      CLIENT_BRANCH_VERSION=$(git -C "$CLIENT_DIR" show "origin/$ARG_BRANCH:package.json" 2>/dev/null | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).version" 2>/dev/null || echo "unknown")
      CLIENT_LOCAL_COMMIT=$(git -C "$CLIENT_DIR" rev-parse --short HEAD 2>/dev/null)
      CLIENT_REMOTE_COMMIT=$(git -C "$CLIENT_DIR" rev-parse --short "origin/$ARG_BRANCH" 2>/dev/null || echo "unknown")
      if [ "$CLIENT_LOCAL_COMMIT" != "$CLIENT_REMOTE_COMMIT" ]; then
        CLIENT_COMMIT_COUNT=$(git -C "$CLIENT_DIR" log --oneline "$CLIENT_LOCAL_COMMIT..$CLIENT_REMOTE_COMMIT" 2>/dev/null | wc -l | tr -d ' ')
        echo "    Client:    v$CLIENT_CURRENT → v$CLIENT_BRANCH_VERSION  ($CLIENT_COMMIT_COUNT new commit(s))"
        BRANCH_HAS_CHANGES=true
      else
        echo "    Client:    v$CLIENT_CURRENT  (up to date)"
      fi
    fi

    if [ "$BRANCH_HAS_CHANGES" = "false" ]; then
      echo ""
      echo "  Everything is up to date on '$ARG_BRANCH'!"
      echo ""
      exit 0
    fi
    ;;
esac

echo ""

# ── Compatibility check (for tag-based updates) ──

if [ "$UPDATE_METHOD" = "tag" ]; then
  # Check if target versions are same or older than current
  if [ "$HAS_BACKEND" = "true" ]; then
    CMP=$(compare_versions "$BACKEND_CURRENT" "$TARGET_BACKEND")
    if [ "$CMP" = "gt" ]; then
      echo "  [!] Warning: Backend would downgrade from v$BACKEND_CURRENT to v$TARGET_BACKEND"
      read -p "  Continue anyway? (y/N): " CONFIRM
      [ "${CONFIRM,,}" = "y" ] || exit 0
    elif [ "$CMP" = "eq" ]; then
      echo "  Backend is already at v$TARGET_BACKEND"
    fi
  fi

  if [ "$HAS_CLIENT" = "true" ]; then
    CMP=$(compare_versions "$CLIENT_CURRENT" "$TARGET_CLIENT")
    if [ "$CMP" = "gt" ]; then
      echo "  [!] Warning: Client would downgrade from v$CLIENT_CURRENT to v$TARGET_CLIENT"
      read -p "  Continue anyway? (y/N): " CONFIRM
      [ "${CONFIRM,,}" = "y" ] || exit 0
    elif [ "$CMP" = "eq" ]; then
      echo "  Client is already at v$TARGET_CLIENT"
    fi
  fi

  # Check client compatibility with backend
  if [ "$HAS_CLIENT" = "true" ] && [ "$HAS_BACKEND" = "true" ]; then
    CLIENT_COMPAT=$(read_remote_compatibility "$CLIENT_DIR" "v$TARGET_CLIENT" 2>/dev/null || echo "")
    if [ -n "$CLIENT_COMPAT" ]; then
      if ! version_satisfies "$TARGET_BACKEND" "$CLIENT_COMPAT"; then
        echo ""
        echo "  [ERROR] Client v$TARGET_CLIENT requires backend $CLIENT_COMPAT"
        echo "  but target backend is v$TARGET_BACKEND"
        exit 1
      fi
    fi
  fi
fi

# ── Compatibility check (for branch updates) ──

if [ "$UPDATE_METHOD" = "branch" ]; then
  if [ "$HAS_CLIENT" = "true" ] && [ "$HAS_BACKEND" = "true" ]; then
    CLIENT_COMPAT=$(read_remote_compatibility "$CLIENT_DIR" "origin/$ARG_BRANCH" 2>/dev/null || echo "")
    if [ -n "$CLIENT_COMPAT" ]; then
      BACKEND_BRANCH_VERSION=$(git -C "$BACKEND_DIR" show "origin/$ARG_BRANCH:package.json" 2>/dev/null | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).version" 2>/dev/null || echo "unknown")
      if [ "$BACKEND_BRANCH_VERSION" != "unknown" ] && ! version_satisfies "$BACKEND_BRANCH_VERSION" "$CLIENT_COMPAT"; then
        echo "  [!] Warning: Client on '$ARG_BRANCH' requires backend $CLIENT_COMPAT"
        echo "  but backend on '$ARG_BRANCH' is v$BACKEND_BRANCH_VERSION"
        read -p "  Continue anyway? (y/N): " CONFIRM
        [ "${CONFIRM,,}" = "y" ] || exit 0
      fi
    fi
  fi
fi

# ── Confirm ──

read -p "  Proceed with update? (Y/n): " CONFIRM
[ "${CONFIRM,,}" != "n" ] || { echo "  Cancelled."; exit 0; }

echo ""

# ── Update backend ──

if [ "$HAS_BACKEND" = "true" ]; then
  if [ "$UPDATE_METHOD" = "tag" ]; then
    CMP=$(compare_versions "$BACKEND_CURRENT" "$TARGET_BACKEND")
    if [ "$CMP" != "eq" ]; then
      echo "── Updating Backend (v$BACKEND_CURRENT → v$TARGET_BACKEND) ──"
      cd "$BACKEND_DIR"
      sudo git checkout "v$TARGET_BACKEND" --quiet
      echo "Installing dependencies..."
      sudo npm install --production=false 2>&1 | tail -1
      echo "Building..."
      sudo npm run build 2>&1 | tail -1
      sudo systemctl restart "$SERVICE_NAME"
      echo "[OK] Backend updated to v$TARGET_BACKEND"
      echo ""
    fi
  else
    echo "── Updating Backend (branch: $ARG_BRANCH) ──"
    cd "$BACKEND_DIR"
    sudo git checkout "$ARG_BRANCH" --quiet 2>/dev/null || sudo git checkout -b "$ARG_BRANCH" "origin/$ARG_BRANCH" --quiet
    sudo git pull origin "$ARG_BRANCH"
    echo "Installing dependencies..."
    sudo npm install --production=false 2>&1 | tail -1
    echo "Building..."
    sudo npm run build 2>&1 | tail -1
    sudo systemctl restart "$SERVICE_NAME"
    BACKEND_NEW=$(read_pkg_version "$BACKEND_DIR")
    echo "[OK] Backend updated to v$BACKEND_NEW ($ARG_BRANCH)"
    echo ""
  fi
fi

# ── Update client ──

if [ "$HAS_CLIENT" = "true" ]; then
  if [ "$UPDATE_METHOD" = "tag" ]; then
    CMP=$(compare_versions "$CLIENT_CURRENT" "$TARGET_CLIENT")
    if [ "$CMP" != "eq" ]; then
      echo "── Updating Client (v$CLIENT_CURRENT → v$TARGET_CLIENT) ──"
      cd "$CLIENT_DIR"
      sudo git checkout "v$TARGET_CLIENT" --quiet
      echo "Installing dependencies..."
      sudo npm install 2>&1 | tail -1
      echo "Building..."
      sudo npm run build 2>&1 | tail -1
      sudo rm -rf "$WEB_ROOT"/*
      sudo cp -r "$CLIENT_DIR/dist/"* "$WEB_ROOT/"
      echo "[OK] Client updated to v$TARGET_CLIENT"
      echo ""
    fi
  else
    echo "── Updating Client (branch: $ARG_BRANCH) ──"
    cd "$CLIENT_DIR"
    sudo git checkout "$ARG_BRANCH" --quiet 2>/dev/null || sudo git checkout -b "$ARG_BRANCH" "origin/$ARG_BRANCH" --quiet
    sudo git pull origin "$ARG_BRANCH"
    echo "Installing dependencies..."
    sudo npm install 2>&1 | tail -1
    echo "Building..."
    sudo npm run build 2>&1 | tail -1
    sudo rm -rf "$WEB_ROOT"/*
    sudo cp -r "$CLIENT_DIR/dist/"* "$WEB_ROOT/"
    CLIENT_NEW=$(read_pkg_version "$CLIENT_DIR")
    echo "[OK] Client updated to v$CLIENT_NEW ($ARG_BRANCH)"
    echo ""
  fi
fi

# ── Summary ──

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║        Update Complete!              ║"
if [ "$UPDATE_METHOD" = "tag" ]; then
echo "  ║  Product:  v$RELEASE_PRODUCT"
[ "$HAS_BACKEND" = "true" ] && echo "  ║  Backend:  v$TARGET_BACKEND"
[ "$HAS_CLIENT" = "true" ] && echo "  ║  Client:   v$TARGET_CLIENT"
else
[ "$HAS_BACKEND" = "true" ] && echo "  ║  Backend:  v$(read_pkg_version "$BACKEND_DIR") ($ARG_BRANCH)"
[ "$HAS_CLIENT" = "true" ] && echo "  ║  Client:   v$(read_pkg_version "$CLIENT_DIR") ($ARG_BRANCH)"
fi
echo "  ╚══════════════════════════════════════╝"
echo ""
