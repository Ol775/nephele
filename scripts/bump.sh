#!/bin/zsh
# Usage: scripts/bump.sh patch|minor|major   Bumps MARKETING_VERSION in project.yml and opens a CHANGELOG section.
set -e
cd "$(dirname "$0")/.."
cur=$(grep -o 'MARKETING_VERSION: "[^"]*"' project.yml | cut -d'"' -f2)
IFS=. read -r a b c <<< "$cur"
case "${1:?patch|minor|major}" in patch) c=$((c+1));; minor) b=$((b+1)); c=0;; major) a=$((a+1)); b=0; c=0;; *) echo "patch|minor|major"; exit 1;; esac
new="$a.$b.$c"
sed -i '' "s/MARKETING_VERSION: \"$cur\"/MARKETING_VERSION: \"$new\"/" project.yml
sed -i '' "s/^## Unreleased$/## Unreleased\n\n## $new/" CHANGELOG.md
echo "$cur -> $new (edit CHANGELOG.md, then commit, push and run scripts/release.sh)"
