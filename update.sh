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
#   bash update.sh --experimental       # follow the development branch (GitLab dev): may break
#   bash update.sh --experimental --insecure   # same, without checking GitLab's TLS certificate
#                                              # (only on a network you trust; asked for every time)
#
# The experimental channel is remembered: once on it, a plain update stays on it until
# --release or --version brings the install back to a stable release.

INSTALL_DIR="${INSTALL_DIR:-/opt/open-helpdesk}"
WEB_ROOT="${WEB_ROOT:-/var/www/openhelpdesk}"
SERVICE_NAME="${SERVICE_NAME:-openhelpdesk-backend}"
GITHUB_UMBRELLA="Hyzokaaa/open-helpdesk"
# Where development happens; public, so no account is needed to read it
GITLAB_CORE="${GITLAB_CORE:-https://gitlab.openhelpdesk.network/open-helpdesk-core}"
CHANNEL_FILE="$INSTALL_DIR/.update-channel"
BACKUP_DIR="${BACKUP_DIR:-$INSTALL_DIR/backups}"

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

current_channel() {
  sudo cat "$CHANNEL_FILE" 2>/dev/null || echo "release"
}

# The GitLab remote sits next to origin (GitHub), which stable releases keep using
ensure_gitlab_remote() {
  local dir=$1
  local repo=$2
  if sudo git -C "$dir" remote get-url gitlab &>/dev/null; then
    sudo git -C "$dir" remote set-url gitlab "$GITLAB_CORE/$repo.git"
  else
    sudo git -C "$dir" remote add gitlab "$GITLAB_CORE/$repo.git"
  fi
}

# A DB_* value from the backend's .env
db_env() {
  sudo grep -E "^$1=" "$BACKEND_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

# Runs psql or pg_dump against the install's database
db_tool() {
  local tool=$1
  shift
  local host port user name
  host=$(db_env DB_HOST); port=$(db_env DB_PORT); user=$(db_env DB_USER); name=$(db_env DB_NAME)
  PGPASSWORD="$(db_env DB_PASSWORD)" "$tool" -h "${host:-localhost}" -p "${port:-5432}" -U "${user:-postgres}" -d "${name:-open_helpdesk}" "$@"
}

# Saves the whole database before the install leaves stable releases; prints the file
backup_database() {
  command -v pg_dump &>/dev/null || return 1
  sudo mkdir -p "$BACKUP_DIR"
  local file
  file="$BACKUP_DIR/before-experimental-$(date +%Y%m%d-%H%M%S).dump"
  db_tool pg_dump -Fc | sudo tee "$file" > /dev/null || return 1
  [ -s "$file" ] || return 1
  echo "$file"
}

# The migrations the database has run, by timestamp
applied_migrations() {
  db_tool psql -tAc 'SELECT "timestamp" FROM migrations' 2>/dev/null | sort -u
}

# The migrations a backend version ships, by timestamp
migrations_in_ref() {
  git -C "$BACKEND_DIR" ls-tree --name-only "$1" src/database/migrations/ 2>/dev/null \
    | sed -n 's#.*/\([0-9]\{13\}\)-.*#\1#p' | sort -u
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

CHANNEL=$(current_channel)

echo "  Current:"
[ "$HAS_BACKEND" = "true" ] && echo "    Backend:   v$BACKEND_CURRENT ($(git -C "$BACKEND_DIR" rev-parse --short HEAD 2>/dev/null))"
[ "$HAS_CLIENT" = "true" ] && echo "    Client:    v$CLIENT_CURRENT ($(git -C "$CLIENT_DIR" rev-parse --short HEAD 2>/dev/null))"
[ "$CHANNEL" = "experimental" ] && echo "    Channel:   experimental (GitLab dev)"
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
  echo ""
  echo "  Open Helpdesk v$RELEASE_PRODUCT is made of backend v$RELEASE_BACKEND and client v$RELEASE_CLIENT:"
  echo "  each component has its own version number, so they need not match the product's."
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
INSECURE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --release)       MODE="release"; shift ;;
    --branch)        MODE="branch"; ARG_BRANCH="${2}"; shift 2 ;;
    --version)       MODE="version"; ARG_VERSION="${2}"; shift 2 ;;
    --experimental)  MODE="experimental"; shift ;;
    --insecure)      INSECURE=true; shift ;;
    *)               echo "  Usage: bash update.sh [--release | --experimental [--insecure] | --branch <name> | --version <x.y.z>]"; exit 1 ;;
  esac
done

# ── Interactive mode ──

if [ -z "$MODE" ]; then
  # On the experimental channel, the plain choice keeps following it
  DEFAULT_CHOICE=1
  [ "$CHANNEL" = "experimental" ] && DEFAULT_CHOICE=4

  echo "  What would you like to do?"
  echo ""
  echo "    1) Update to latest stable release (v${RELEASE_PRODUCT:-?}) — recommended"
  echo "    2) Update to latest branch commit (advanced)"
  echo "    3) Update to a specific product version"
  echo "    4) Experimental: latest development (GitLab dev) — may break"
  echo "    0) Cancel"
  echo ""
  read -p "  Choose [$DEFAULT_CHOICE]: " CHOICE
  CHOICE="${CHOICE:-$DEFAULT_CHOICE}"

  case "$CHOICE" in
    1) MODE="release" ;;
    4) MODE="experimental" ;;
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

# ── Experimental channel: the dev branch, from GitLab ──

REMOTE="origin"
EXPERIMENTAL=false
if [ "$MODE" = "experimental" ]; then
  if [ "$CHANNEL" != "experimental" ]; then
    echo "  [!] The experimental channel installs the latest development work, before it is"
    echo "      released. It may break, and it may change the database in ways an older"
    echo "      release does not understand: going back to a release then needs a backup of"
    echo "      the database from before (yours, or one this update can take next)."
    echo ""
    read -p "  Switch this install to the experimental channel? (y/N): " CONFIRM
    [ "${CONFIRM,,}" = "y" ] || { echo "  Cancelled."; exit 0; }
    echo ""
  fi
  [ "$HAS_BACKEND" = "true" ] && ensure_gitlab_remote "$BACKEND_DIR" backend
  [ "$HAS_CLIENT" = "true" ] && ensure_gitlab_remote "$CLIENT_DIR" client
  MODE="branch"
  REMOTE="gitlab"
  ARG_BRANCH="dev"
  EXPERIMENTAL=true
fi
if [ "$INSECURE" = "true" ]; then
  if [ "$EXPERIMENTAL" != "true" ]; then
    echo "  [ERROR] --insecure only goes with --experimental."; exit 1
  fi
  echo "  [!] TLS verification is off for GitLab: use it only on a network you trust."
  echo ""
fi
# The local branch: "experimental" for GitLab's dev, so it never mixes with origin's branches
LOCAL_BRANCH="$ARG_BRANCH"
[ "$EXPERIMENTAL" = "true" ] && LOCAL_BRANCH="experimental"

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
    if [ "$EXPERIMENTAL" = "true" ]; then
      echo "  Updating to the latest development work (GitLab dev)"
    else
      echo "  Updating to latest commit on branch '$ARG_BRANCH'"
    fi

    BRANCH_HAS_CHANGES=false

    # Fetch the target branch explicitly, into its remote-tracking ref whatever the git version or
    # remote config; stop here, before anything changes, if it cannot be fetched
    fetch_branch() {
      local dir=$1 name=$2 output
      # --insecure touches only this fetch from GitLab; GitHub, releases and npm still check certificates
      local tls=()
      [ "$INSECURE" = "true" ] && tls=(-c http.sslVerify=false)
      if ! output=$(sudo git "${tls[@]}" -C "$dir" fetch "$REMOTE" "+refs/heads/$ARG_BRANCH:refs/remotes/$REMOTE/$ARG_BRANCH" --quiet 2>&1) \
        || ! git -C "$dir" rev-parse --verify --quiet "$REMOTE/$ARG_BRANCH" > /dev/null; then
        echo ""
        echo "  [ERROR] Could not fetch '$ARG_BRANCH' for the $name from $(git -C "$dir" remote get-url "$REMOTE" 2>/dev/null || echo "$REMOTE")"
        [ -n "$output" ] && echo "$output" | sed 's/^/          /'
        if echo "$output" | grep -qiE "certificate|ssl|tls" && [ "$INSECURE" != "true" ]; then
          echo "  If this server reaches GitLab through a network you trust, you can run it again with"
          echo "  --insecure to skip the certificate check for GitLab."
        fi
        echo "  Nothing was changed."
        exit 1
      fi
    }
    [ "$HAS_BACKEND" = "true" ] && fetch_branch "$BACKEND_DIR" "backend"
    [ "$HAS_CLIENT" = "true" ] && fetch_branch "$CLIENT_DIR" "client"

    if [ "$HAS_BACKEND" = "true" ]; then
      BACKEND_BRANCH_VERSION=$(git -C "$BACKEND_DIR" show "$REMOTE/$ARG_BRANCH:package.json" 2>/dev/null | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).version" 2>/dev/null || echo "unknown")
      BACKEND_LOCAL_COMMIT=$(git -C "$BACKEND_DIR" rev-parse --short HEAD 2>/dev/null)
      BACKEND_REMOTE_COMMIT=$(git -C "$BACKEND_DIR" rev-parse --short "$REMOTE/$ARG_BRANCH" 2>/dev/null || echo "unknown")
      if [ "$BACKEND_LOCAL_COMMIT" != "$BACKEND_REMOTE_COMMIT" ]; then
        BACKEND_COMMIT_COUNT=$(git -C "$BACKEND_DIR" log --oneline "$BACKEND_LOCAL_COMMIT..$BACKEND_REMOTE_COMMIT" 2>/dev/null | wc -l | tr -d ' ')
        echo "    Backend:   v$BACKEND_CURRENT → v$BACKEND_BRANCH_VERSION  ($BACKEND_COMMIT_COUNT new commit(s))"
        BRANCH_HAS_CHANGES=true
      else
        echo "    Backend:   v$BACKEND_CURRENT  (up to date)"
      fi
    fi

    if [ "$HAS_CLIENT" = "true" ]; then
      CLIENT_BRANCH_VERSION=$(git -C "$CLIENT_DIR" show "$REMOTE/$ARG_BRANCH:package.json" 2>/dev/null | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).version" 2>/dev/null || echo "unknown")
      CLIENT_LOCAL_COMMIT=$(git -C "$CLIENT_DIR" rev-parse --short HEAD 2>/dev/null)
      CLIENT_REMOTE_COMMIT=$(git -C "$CLIENT_DIR" rev-parse --short "$REMOTE/$ARG_BRANCH" 2>/dev/null || echo "unknown")
      if [ "$CLIENT_LOCAL_COMMIT" != "$CLIENT_REMOTE_COMMIT" ]; then
        CLIENT_COMMIT_COUNT=$(git -C "$CLIENT_DIR" log --oneline "$CLIENT_LOCAL_COMMIT..$CLIENT_REMOTE_COMMIT" 2>/dev/null | wc -l | tr -d ' ')
        echo "    Client:    v$CLIENT_CURRENT → v$CLIENT_BRANCH_VERSION  ($CLIENT_COMMIT_COUNT new commit(s))"
        BRANCH_HAS_CHANGES=true
      else
        echo "    Client:    v$CLIENT_CURRENT  (up to date)"
      fi
    fi

    if [ "$BRANCH_HAS_CHANGES" = "false" ]; then
      [ "$EXPERIMENTAL" = "true" ] && echo "experimental" | sudo tee "$CHANNEL_FILE" > /dev/null
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
    elif [ "$CMP" = "eq" ] && [ "$CHANNEL" != "experimental" ]; then
      echo "  Backend is already at v$TARGET_BACKEND"
    fi
  fi

  if [ "$HAS_CLIENT" = "true" ]; then
    CMP=$(compare_versions "$CLIENT_CURRENT" "$TARGET_CLIENT")
    if [ "$CMP" = "gt" ]; then
      echo "  [!] Warning: Client would downgrade from v$CLIENT_CURRENT to v$TARGET_CLIENT"
      read -p "  Continue anyway? (y/N): " CONFIRM
      [ "${CONFIRM,,}" = "y" ] || exit 0
    elif [ "$CMP" = "eq" ] && [ "$CHANNEL" != "experimental" ]; then
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
    CLIENT_COMPAT=$(read_remote_compatibility "$CLIENT_DIR" "$REMOTE/$ARG_BRANCH" 2>/dev/null || echo "")
    if [ -n "$CLIENT_COMPAT" ]; then
      BACKEND_BRANCH_VERSION=$(git -C "$BACKEND_DIR" show "$REMOTE/$ARG_BRANCH:package.json" 2>/dev/null | node -p "JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8')).version" 2>/dev/null || echo "unknown")
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

# ── Entering the experimental channel: a copy of the database, if wanted ──
# Off unless asked: a large database takes long and fills the disk, and installs often back up already

if [ "$EXPERIMENTAL" = "true" ] && [ "$CHANNEL" != "experimental" ] && [ "$HAS_BACKEND" = "true" ]; then
  read -p "  Back up the database first, in $BACKUP_DIR? (y/N): " CONFIRM
  if [ "${CONFIRM,,}" = "y" ]; then
    echo "── Backing up the database ──"
    if BACKUP_FILE=$(backup_database); then
      echo "[OK] Saved to $BACKUP_FILE"
      echo "     To go back to a release with this data: pg_restore --clean -d <database> $BACKUP_FILE"
    else
      echo "  [!] The database could not be backed up (pg_dump missing or failed)."
      read -p "  Continue without a backup? (y/N): " CONFIRM
      [ "${CONFIRM,,}" = "y" ] || exit 0
    fi
  fi
  echo ""
fi

# ── Leaving the experimental channel: the release must understand the database ──

if [ "$UPDATE_METHOD" = "tag" ] && [ "$CHANNEL" = "experimental" ] && [ "$HAS_BACKEND" = "true" ]; then
  APPLIED=$(applied_migrations)
  if [ -n "$APPLIED" ]; then
    UNKNOWN=$(comm -23 <(echo "$APPLIED") <(migrations_in_ref "v$TARGET_BACKEND"))
    if [ -n "$UNKNOWN" ]; then
      echo "  [!] The database has $(echo "$UNKNOWN" | wc -l | tr -d ' ') change(s) from development that backend"
      echo "      v$TARGET_BACKEND does not know. It may not start, or misread the data."
      echo "      Safest: restore a backup of the database from before the install joined the"
      echo "      experimental channel, then update; changes made since are lost."
      LATEST_BACKUP=$(sudo ls -1t "$BACKUP_DIR"/before-experimental-*.dump 2>/dev/null | head -1)
      [ -n "$LATEST_BACKUP" ] && echo "      Latest backup: $LATEST_BACKUP"
      echo ""
      read -p "  Type 'yes' to go back anyway: " CONFIRM
      [ "$CONFIRM" = "yes" ] || { echo "  Cancelled."; exit 0; }
      echo ""
    fi
  else
    echo "  [!] Could not read the database's migrations to check them; going on."
    echo ""
  fi
fi

# ── Update backend ──

if [ "$HAS_BACKEND" = "true" ]; then
  if [ "$UPDATE_METHOD" = "tag" ]; then
    CMP=$(compare_versions "$BACKEND_CURRENT" "$TARGET_BACKEND")
    # Coming from the experimental channel the same number may hide other code: always check out
    if [ "$CMP" != "eq" ] || [ "$CHANNEL" = "experimental" ]; then
      echo "── Updating Backend (v$BACKEND_CURRENT → v$TARGET_BACKEND) ──"
      cd "$BACKEND_DIR"
      sudo git checkout -- package-lock.json 2>/dev/null || true
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
    sudo git checkout -- package-lock.json 2>/dev/null || true
    sudo git checkout -B "$LOCAL_BRANCH" "$REMOTE/$ARG_BRANCH" --quiet
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
    # Coming from the experimental channel the same number may hide other code: always check out
    if [ "$CMP" != "eq" ] || [ "$CHANNEL" = "experimental" ]; then
      echo "── Updating Client (v$CLIENT_CURRENT → v$TARGET_CLIENT) ──"
      cd "$CLIENT_DIR"
      sudo git checkout -- package-lock.json 2>/dev/null || true
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
    sudo git checkout -- package-lock.json 2>/dev/null || true
    sudo git checkout -B "$LOCAL_BRANCH" "$REMOTE/$ARG_BRANCH" --quiet
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

# ── nginx: websocket upgrade for live updates ──
# Older installs proxy /api/ without the upgrade headers, so live updates fall back to
# long-polling. That works, but point out the fix; the config is never edited here, since
# certbot and admins change it.

NGINX_SITE="${NGINX_SITE:-openhelpdesk}"
for NGINX_CONF in "/etc/nginx/sites-available/$NGINX_SITE.conf" "/etc/nginx/conf.d/$NGINX_SITE.conf"; do
  if [ -f "$NGINX_CONF" ] && ! grep -qs "http_upgrade" "$NGINX_CONF"; then
    echo "[NOTE] Live updates are using long-polling because $NGINX_CONF"
    echo "       does not forward websocket upgrades. To enable websockets, add inside"
    echo "       'location /api/ { ... }':"
    echo ""
    echo "           proxy_http_version 1.1;"
    echo "           proxy_set_header Upgrade \$http_upgrade;"
    echo "           proxy_set_header Connection \$http_connection;"
    echo ""
    echo "       then run: sudo nginx -t && sudo systemctl reload nginx"
    echo ""
  fi
done

# ── Remember the channel ──

if [ "$EXPERIMENTAL" = "true" ]; then
  echo "experimental" | sudo tee "$CHANNEL_FILE" > /dev/null
else
  sudo rm -f "$CHANNEL_FILE"
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
[ "$HAS_BACKEND" = "true" ] && echo "  ║  Backend:  v$(read_pkg_version "$BACKEND_DIR") ($ARG_BRANCH, $(git -C "$BACKEND_DIR" rev-parse --short HEAD 2>/dev/null))"
[ "$HAS_CLIENT" = "true" ] && echo "  ║  Client:   v$(read_pkg_version "$CLIENT_DIR") ($ARG_BRANCH, $(git -C "$CLIENT_DIR" rev-parse --short HEAD 2>/dev/null))"
[ "$EXPERIMENTAL" = "true" ] && echo "  ║  Channel:  experimental (back with --release)"
fi
echo "  ╚══════════════════════════════════════╝"
echo ""
