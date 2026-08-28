#!/bin/bash
set -e

# Open Helpdesk - Component Version Bump
# Bumps the version of a single component, tags it, and creates a GitHub Release.
#
# Usage:
#   bash bump.sh backend 1.21.0
#   bash bump.sh client patch
#   bash bump.sh backend minor
#
# Supports: backend, client

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

COMPONENT="${1}"
VERSION_ARG="${2}"

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║     Component Version Bump           ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# ── Validate component ──

case "$COMPONENT" in
  backend)  REPO_DIR="$PARENT_DIR/backend" ;;
  client)   REPO_DIR="$PARENT_DIR/client" ;;
  *)
    echo "  Usage: bash bump.sh <backend|client> <version|major|minor|patch>"
    exit 1
    ;;
esac

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "  [ERROR] Git repo not found: $REPO_DIR"
  exit 1
fi

# ── Read current version ──

CURRENT_VERSION=$(node -p "require('$REPO_DIR/package.json').version" 2>/dev/null)
echo "  Component:  $COMPONENT"
echo "  Current:    v$CURRENT_VERSION"

# ── Calculate new version ──

bump_version() {
  local version=$1
  local type=$2
  IFS='.' read -r major minor patch <<< "$version"
  case "$type" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
    *)     echo "$type" ;;
  esac
}

if [ -z "$VERSION_ARG" ]; then
  read -p "  New version (or major/minor/patch): " VERSION_ARG
fi

case "$VERSION_ARG" in
  major|minor|patch)
    NEW_VERSION=$(bump_version "$CURRENT_VERSION" "$VERSION_ARG")
    ;;
  *)
    NEW_VERSION="$VERSION_ARG"
    ;;
esac

if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "  [ERROR] Invalid version format: $NEW_VERSION"
  exit 1
fi

if [ "$NEW_VERSION" = "$CURRENT_VERSION" ]; then
  echo "  [ERROR] New version is the same as current: $CURRENT_VERSION"
  exit 1
fi

echo "  New:        v$NEW_VERSION"
echo ""

# ── Check for existing tag ──

git -C "$REPO_DIR" fetch origin --tags --quiet
if git -C "$REPO_DIR" tag -l "v$NEW_VERSION" | grep -q "v$NEW_VERSION"; then
  echo "  [ERROR] Tag v$NEW_VERSION already exists in $COMPONENT"
  exit 1
fi

# ── Check current branch ──

BRANCH=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$BRANCH" != "dev" ]; then
  echo "  [WARN] Not on dev branch (currently on $BRANCH)"
  read -p "  Continue anyway? (y/N): " BRANCH_CONFIRM
  if [ "${BRANCH_CONFIRM,,}" != "y" ]; then
    echo "  Cancelled."
    exit 0
  fi
fi

# ── Check for uncommitted changes ──

if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
  echo "  [ERROR] $COMPONENT has uncommitted changes. Commit or stash first."
  exit 1
fi

# ── Confirm ──

echo "  Will:"
echo "    1. Update package.json version to $NEW_VERSION"
echo "    2. Commit and push to $BRANCH"
echo "    3. Create tag v$NEW_VERSION (on $BRANCH)"
echo "    4. Push tag and create GitHub Release"
echo ""
read -p "  Proceed? (Y/n): " CONFIRM
if [ "${CONFIRM,,}" = "n" ]; then
  echo "  Cancelled."
  exit 0
fi
echo ""

# ── Update package.json ──

echo "── Updating package.json ──"
node -e "
const fs = require('fs');
const path = '$REPO_DIR/package.json';
const pkg = JSON.parse(fs.readFileSync(path, 'utf-8'));
pkg.version = '$NEW_VERSION';
fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + '\n');
"
echo "  [OK] $COMPONENT → v$NEW_VERSION"

# ── Commit and push ──

echo "── Committing ──"
git -C "$REPO_DIR" add package.json
git -C "$REPO_DIR" commit -m "chore: bump version to $NEW_VERSION"
git -C "$REPO_DIR" push origin "$BRANCH"
echo "  [OK] Pushed to $BRANCH"

# ── Tag and push ──

echo "── Tagging ──"
git -C "$REPO_DIR" tag "v$NEW_VERSION"
git -C "$REPO_DIR" push origin "v$NEW_VERSION"
echo "  [OK] Tag v$NEW_VERSION pushed"

# ── GitHub Release ──

echo "── Creating GitHub Release ──"
REPO_URL=$(git -C "$REPO_DIR" remote get-url origin | sed 's/\.git$//')
gh release create "v$NEW_VERSION" \
  --repo "$REPO_URL" \
  --title "v$NEW_VERSION" \
  --generate-notes 2>/dev/null && echo "  [OK] Release created" || echo "  [SKIP] Release may already exist"

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║        Bump Complete!                ║"
echo "  ║  $COMPONENT: v$CURRENT_VERSION → v$NEW_VERSION"
echo "  ╚══════════════════════════════════════╝"
echo ""
