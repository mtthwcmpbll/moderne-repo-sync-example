#!/bin/bash
set -e

# Configuration
: "${ORIGIN_REPO:=git@github.com:mtthwcmpbll/moderne-repo-sync-origin.git}"
: "${DEST_REPO:=git@github.com:mtthwcmpbll/moderne-repo-sync-destination.git}"
WORK_DIR="work-dir"

# Helper to check for command existence
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo "Syncing from $ORIGIN_REPO to $DEST_REPO..."

# Cleanup previous run
rm -rf "$WORK_DIR"

# Clone origin
echo "Cloning origin..."
git clone "$ORIGIN_REPO" "$WORK_DIR"
cd "$WORK_DIR"

# Setup LFS and pull if available
if git lfs version >/dev/null 2>&1; then
    echo "Pulling LFS objects..."
    git lfs install
    git lfs pull
else
    echo "Warning: git-lfs not found. Skipping LFS operations."
fi

# Fetch all branches
for remote in $(git branch -r | grep -v '\->'); do
    if [ "$remote" != "origin/HEAD" ] && [ "$remote" != "origin/$(git branch --show-current)" ]; then
        git branch --track "${remote#origin/}" "$remote" || true
    fi
done

# Run Moderne CLI transformations
rm $HOME/.moderne/cli/maven-cache.cache 2>/dev/null || true

if [ -f "../recipes.conf" ]; then
    echo "Running Moderne CLI transformations..."
    echo "Applying recipes from recipes.conf..."
    while IFS= read -r recipe_cmd || [ -n "$recipe_cmd" ]; do
        # build the latest LST before applying the recipe
        mod build .

        # Skip empty lines and comments
        [[ -z "$recipe_cmd" || "$recipe_cmd" =~ ^# ]] && continue
        
        echo "Running recipe: $recipe_cmd"
        # We need to eval here to correctly handle quotes in arguments
        eval "mod run . --recipe $recipe_cmd"
    done < "../recipes.conf"
else
    echo "Warning: recipes.conf not found. Skipping recipe application."
fi
# Apply changes and commit using Moderne CLI
mod git apply . --last-recipe-run
mod git add . --last-recipe-run
mod git commit . --last-recipe-run -m "Apply Moderne transformations"

# Push to destination
echo "Pushing to destination..."
git remote add dest "$DEST_REPO"
git push dest --all --force
git push dest --tags --force

if git lfs version >/dev/null 2>&1; then
    git lfs push dest --all
fi

echo "Sync complete."
