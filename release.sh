#!/bin/bash
set -e

# Open Helpdesk - Core Release Script
# Creates a product release by tagging components and updating the manifest.
#
# Prerequisites:
#   - gh CLI authenticated
#   - All repos as sibling directories (../backend, ../client)
#   - Changes already merged to main in all repos
#
# Usage:
#   bash release.sh 1.21.0
#   bash release.sh minor
#   bash release.sh patch

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

BACKEND_DIR="$PARENT_DIR/backend"
CLIENT_DIR="$PARENT_DIR/client"
UMBRELLA_DIR="$SCRIPT_DIR"

# ── Helpers ──

to_node_path() {
  if [[ "$1" =~ ^/([a-zA-Z])/ ]]; then
    echo "${BASH_REMATCH[1]^}:/${1:3}"
  else
    echo "$1"
  fi
}

read_pkg_field() {
  local file="$1"
  local field="$2"
  grep "\"$field\"" "$file" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/'
}

read_json_first() {
  local file="$1"
  local field="$2"
  grep "\"$field\"" "$file" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/'
}

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

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║     Open Helpdesk Release            ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# ── Resolve current product version ──

RELEASES_FILE="$UMBRELLA_DIR/releases.json"
CURRENT_PRODUCT=""
if [ -f "$RELEASES_FILE" ]; then
  CURRENT_PRODUCT=$(read_json_first "$RELEASES_FILE" "product")
fi

# ── Validate args ──

VERSION_ARG="${1}"
if [ -z "$VERSION_ARG" ]; then
  echo "  Current product version: v${CURRENT_PRODUCT:-unknown}"
  read -p "  New version (or major/minor/patch): " VERSION_ARG
fi

if [ -z "$VERSION_ARG" ]; then
  echo "  [ERROR] Version is required. Usage: bash release.sh <version|major|minor|patch>"
  exit 1
fi

case "$VERSION_ARG" in
  major|minor|patch)
    if [ -z "$CURRENT_PRODUCT" ]; then
      echo "  [ERROR] Cannot auto-bump: no current product version found in releases.json"
      exit 1
    fi
    VERSION=$(bump_version "$CURRENT_PRODUCT" "$VERSION_ARG")
    ;;
  *)
    VERSION="$VERSION_ARG"
    ;;
esac

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "  [ERROR] Invalid version format. Use semver: X.Y.Z"
  exit 1
fi

echo "  Releasing Open Helpdesk v$VERSION"
echo ""

# ── Validate repos exist ──

for DIR in "$BACKEND_DIR" "$CLIENT_DIR" "$UMBRELLA_DIR"; do
  if [ ! -d "$DIR/.git" ]; then
    echo "  [ERROR] Git repo not found: $DIR"
    exit 1
  fi
done

# ── Check gh CLI ──

if ! command -v gh &>/dev/null; then
  echo "  [ERROR] gh CLI is required. Install: https://cli.github.com"
  exit 1
fi

# ── Fetch latest main in all repos ──

echo "── Fetching latest from origin ──"
for DIR in "$BACKEND_DIR" "$CLIENT_DIR" "$UMBRELLA_DIR"; do
  REPO_NAME=$(basename "$DIR")
  git -C "$DIR" fetch origin main --quiet
  echo "  [OK] $REPO_NAME"
done
echo ""

# ── Check that main is up to date with dev ──

echo "── Checking main is up to date ──"
for DIR in "$BACKEND_DIR" "$CLIENT_DIR"; do
  REPO_NAME=$(basename "$DIR")
  git -C "$DIR" fetch origin dev --quiet 2>/dev/null || true

  MAIN_COMMIT=$(git -C "$DIR" rev-parse origin/main 2>/dev/null)
  DEV_COMMIT=$(git -C "$DIR" rev-parse origin/dev 2>/dev/null)

  if [ "$MAIN_COMMIT" != "$DEV_COMMIT" ]; then
    BEHIND=$(git -C "$DIR" rev-list --count origin/main..origin/dev 2>/dev/null || echo "?")
    echo "  [WARN] $REPO_NAME: dev is $BEHIND commit(s) ahead of main"
    echo "         Merge dev → main before releasing."
  else
    echo "  [OK] $REPO_NAME: main is up to date"
  fi
done
echo ""

# ── Read component versions ──

BACKEND_VERSION=$(read_pkg_field "$BACKEND_DIR/package.json" "version")
CLIENT_VERSION=$(read_pkg_field "$CLIENT_DIR/package.json" "version")

echo "── Component versions ──"
echo "  backend:  v$BACKEND_VERSION"
echo "  client:   v$CLIENT_VERSION"
echo ""

# ── Check changelog ──

CHANGELOG_FILE="$BACKEND_DIR/src/changelog/changelog.data.ts"
if grep -q "version: '$VERSION'" "$CHANGELOG_FILE" 2>/dev/null; then
  echo "  [OK] Changelog has entry for v$VERSION"
else
  echo "  [WARN] Changelog does not have entry for v$VERSION"
  echo "         File: $CHANGELOG_FILE"
fi
echo ""

# ── Check for existing tags ──

for DIR in "$BACKEND_DIR" "$CLIENT_DIR" "$UMBRELLA_DIR"; do
  REPO_NAME=$(basename "$DIR")
  if git -C "$DIR" tag -l "v$VERSION" | grep -q "v$VERSION"; then
    echo "  [ERROR] Tag v$VERSION already exists in $REPO_NAME"
    exit 1
  fi
done

# ── Confirm ──

echo "  Will create:"
echo "    - Tag v$VERSION on main in backend, client, umbrella"
echo "    - GitHub Release v$VERSION in each repo"
echo "    - Update releases.json"
echo ""
read -p "  Proceed? (Y/n): " CONFIRM
if [ "${CONFIRM,,}" = "n" ]; then
  echo "  Release cancelled."
  exit 0
fi
echo ""

# ── Update releases.json ──

echo "── Updating releases.json ──"
DATE=$(date +%Y-%m-%d)

NODE_RELEASES_PATH=$(to_node_path "$RELEASES_FILE")
TEMP_FILE=$(mktemp)
NODE_TEMP_PATH=$(to_node_path "$TEMP_FILE")

node -e "
const fs = require('fs');
const releases = JSON.parse(fs.readFileSync('$NODE_RELEASES_PATH', 'utf-8'));
releases.unshift({
  product: '$VERSION',
  date: '$DATE',
  components: {
    backend: '$BACKEND_VERSION',
    client: '$CLIENT_VERSION'
  }
});
fs.writeFileSync('$NODE_TEMP_PATH', JSON.stringify(releases, null, 2) + '\n');
"
mv "$TEMP_FILE" "$RELEASES_FILE"

git -C "$UMBRELLA_DIR" add releases.json
git -C "$UMBRELLA_DIR" commit -m "release: v$VERSION"
git -C "$UMBRELLA_DIR" push origin dev
echo "  [OK] releases.json updated"
echo ""

# ── Create tags on main ──

echo "── Creating tags ──"
for DIR in "$BACKEND_DIR" "$CLIENT_DIR" "$UMBRELLA_DIR"; do
  REPO_NAME=$(basename "$DIR")
  git -C "$DIR" tag "v$VERSION" origin/main
  git -C "$DIR" push origin "v$VERSION"
  echo "  [OK] $REPO_NAME → v$VERSION"
done
echo ""

# ── Create GitHub Releases ──

echo "── Creating GitHub Releases ──"

# Extract changelog for this version
RELEASE_NOTES="See changelog for details."
NODE_CHANGELOG_PATH=$(to_node_path "$CHANGELOG_FILE")
if [ -f "$CHANGELOG_FILE" ]; then
  RELEASE_NOTES=$(node -e "
    const fs = require('fs');
    const content = fs.readFileSync('$NODE_CHANGELOG_PATH', 'utf-8');
    const versionBlock = content.split(\"version: '$VERSION'\")[1];
    if (!versionBlock) { console.log('See changelog for details.'); process.exit(0); }
    const categories = versionBlock.split(\"title: { en: '\").slice(1);
    let md = '';
    for (const cat of categories) {
      const titleEnd = cat.indexOf(\"'\");
      if (titleEnd === -1) continue;
      const title = cat.substring(0, titleEnd);
      md += '## ' + title + '\n';
      const features = cat.split(\"en: '\").slice(1);
      for (const f of features) {
        const fEnd = f.indexOf(\"'\");
        if (fEnd === -1) continue;
        const nextVersion = f.indexOf(\"version: '\");
        if (nextVersion !== -1 && nextVersion < fEnd) break;
        md += '- ' + f.substring(0, fEnd) + '\n';
      }
      md += '\n';
      if (cat.includes(\"version: '\") && !cat.startsWith(title)) break;
    }
    console.log(md.trim());
  " 2>/dev/null || echo "See changelog for details.")
fi

gh release create "v$VERSION" \
  --repo "$(git -C "$BACKEND_DIR" remote get-url origin | sed 's/\.git$//')" \
  --title "v$VERSION" \
  --notes "$RELEASE_NOTES" 2>/dev/null && echo "  [OK] backend" || echo "  [SKIP] backend (release may already exist)"

gh release create "v$VERSION" \
  --repo "$(git -C "$CLIENT_DIR" remote get-url origin | sed 's/\.git$//')" \
  --title "v$VERSION" \
  --notes "$RELEASE_NOTES" 2>/dev/null && echo "  [OK] client" || echo "  [SKIP] client (release may already exist)"

gh release create "v$VERSION" \
  --repo "$(git -C "$UMBRELLA_DIR" remote get-url origin | sed 's/\.git$//')" \
  --title "v$VERSION" \
  --notes "$(cat <<EOF
Open Helpdesk v$VERSION

Components:
- backend: v$BACKEND_VERSION
- client: v$CLIENT_VERSION
EOF
)" 2>/dev/null && echo "  [OK] umbrella" || echo "  [SKIP] umbrella (release may already exist)"

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║        Release Complete!             ║"
echo "  ║  Product:  v$VERSION"
echo "  ║  Backend:  v$BACKEND_VERSION"
echo "  ║  Client:   v$CLIENT_VERSION"
echo "  ╚══════════════════════════════════════╝"
echo ""
