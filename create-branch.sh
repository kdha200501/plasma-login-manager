#!/bin/bash

PACKAGE="plasma-login-manager"

# Parse options
while getopts "f:h" opt; do
  case $opt in
    f) FEDORA_VERSION="$OPTARG" ;;
    h)
      cat <<EOF
Branch off from an upstream branch of $PACKAGE.

Usage: $0 [-f fedora_version]
  -f  Specify the Fedora release version
  -h  Show this help message

Example:
  $0
  $0 -f 43
EOF
      exit 0
      ;;
    *)
      echo "Usage: $0 [-f fedora_version]" >&2
      exit 1
      ;;
  esac
done

# Set Fedora release version
if [ -z "$FEDORA_VERSION" ]; then
  # Find the host's Fedora version
  HOST_FEDORA_VERSION=$(rpm -E %fedora)

  read -rp "Fedora release version (default: $HOST_FEDORA_VERSION): " FEDORA_VERSION
  FEDORA_VERSION="${FEDORA_VERSION:-$HOST_FEDORA_VERSION}"
fi

# Find the latest version for the package
TMP_OUTPUT=$(mktemp)
printf "\r\e[K🔍 Querying the latest version for package %s" "$PACKAGE"
dnf --releasever="$FEDORA_VERSION" repoquery --queryformat="%{VERSION}" --latest-limit=1 "$PACKAGE" 2>&1 | tee "$TMP_OUTPUT" | while read -r line; do
  printf "\r\e[K🔍 %s" "${line:0:(($COLUMNS - 3))}"
done

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  printf "\r\e[K❌ Failed to query the latest version for package %s\n" "$PACKAGE"
  rm -f "$TMP_OUTPUT"
  exit 1
fi

PACKAGE_VERSION=$(tail -n 1 "$TMP_OUTPUT")
printf "\r\e[K"
rm -f "$TMP_OUTPUT"

if [ -z "$PACKAGE_VERSION" ]; then
  echo "❌ No package version found"
  exit 1
fi

printf "\r\e[K📦 Package version: %s\n" "$PACKAGE_VERSION"

# Fetch the corresponding branch from upstream
UPSTREAM_BRANCH="f$FEDORA_VERSION"
printf "\r\e[K📥 Fetching branch %s from upstream" "$UPSTREAM_BRANCH"
git fetch --no-tags upstream "refs/heads/$UPSTREAM_BRANCH:refs/upstream/$UPSTREAM_BRANCH" 2>&1 | while read -r line; do
  printf "\r\e[K📥 %s" "${line:0:(($COLUMNS - 3))}"
done

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  printf "\r\e[K❌ Failed to fetch branch %s from upstream\n" "$UPSTREAM_BRANCH"
  exit 1
fi

printf "\r\e[K🌿 Upstream branch: %s\n" "$UPSTREAM_BRANCH"

# Validate version from upstream spec file
TMP_DIR=$(mktemp -d)
git show "refs/upstream/$UPSTREAM_BRANCH:$PACKAGE.spec" > "$TMP_DIR/$PACKAGE.spec" 2>/dev/null || {
  printf "\r\e[K❌ Failed to read %s.spec from upstream branch %s\n" "$PACKAGE" "$UPSTREAM_BRANCH"
  rm -rf "$TMP_DIR"
  exit 1
}

UPSTREAM_VERSION=$(rpmspec --query --queryformat='%{VERSION}' --srpm "$TMP_DIR/$PACKAGE.spec" 2>/dev/null)
rm -rf "$TMP_DIR"

if [ "$UPSTREAM_VERSION" != "$PACKAGE_VERSION" ]; then
  printf "\r\e[K❌ Upstream version %s does not match package version %s\n" "$UPSTREAM_VERSION" "$PACKAGE_VERSION"
  exit 1
fi

printf "\r\e[K🏷 Upstream version: %s\n" "$UPSTREAM_VERSION"

# List commits to cherry-pick
BRANCH="customize/v$PACKAGE_VERSION"
read -rp "Show commits to cherry-pick onto $BRANCH? [Y/n] " SHOW_COMMITS
SHOW_COMMITS="${SHOW_COMMITS:-y}"
if [[ "${SHOW_COMMITS,,}" == "y" ]]; then
  BRANCH_COMMIT=$(git rev-parse refs/upstream/$UPSTREAM_BRANCH)

  YOUNGEST_BRANCH=""
  YOUNGEST_TAG=""
  YOUNGEST_TIME=0

  while IFS= read -r remote_branch; do
    common_ancestor_commit=$(git merge-base "$remote_branch" "$BRANCH_COMMIT" 2>/dev/null)
    [ -z "$common_ancestor_commit" ] && continue

    tag=$(git for-each-ref --contains "$common_ancestor_commit" --sort=creatordate --format='%(refname:short)' refs/upstream/ | head -1)
    [ -z "$tag" ] && continue

    tag_time_in_sec=$(git log -1 --format=%at "$tag" 2>/dev/null)
    [ -z "$tag_time_in_sec" ] && continue

    [ "$tag_time_in_sec" -lt "$YOUNGEST_TIME" ] && continue

    YOUNGEST_TIME="$tag_time_in_sec"
    YOUNGEST_BRANCH="$remote_branch"
    YOUNGEST_TAG="$tag"
  done < <(git branch -r | grep 'origin/customize/' | sed 's/^ *//')

  if [ -n "$YOUNGEST_BRANCH" ] && [ -n "$YOUNGEST_TAG" ]; then
    echo "🍒 Commits from $YOUNGEST_BRANCH (based on $YOUNGEST_TAG):"
    git log --oneline --no-decorate "$YOUNGEST_TAG..$YOUNGEST_BRANCH"
  else
    echo "⚠ No existing customize branches found to cherry-pick from"
  fi
fi


# Branch off upstream branch
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  printf "\r\e[K🟢 Branch %s already exists\n" "$BRANCH"
  git checkout "$BRANCH" &>/dev/null
  exit 0
fi

git checkout "refs/upstream/$UPSTREAM_BRANCH" -b "$BRANCH" &>/dev/null
printf "\r\e[K✨ New branch %s created\n" "$BRANCH"
