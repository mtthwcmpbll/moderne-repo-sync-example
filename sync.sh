#!/bin/bash
set -e

# Configuration
: "${ORIGIN_REPO:=git@github.com:mtthwcmpbll/moderne-repo-sync-origin.git}"
: "${DEST_REPO:=git@github.com:mtthwcmpbll/moderne-repo-sync-destination.git}"

# Configure auth if token is provided
if [ -n "$GITHUB_TOKEN" ]; then
    # Convert SSH URLs to HTTPS with token
    # expected format: git@github.com:user/repo.git -> https://x-access-token:TOKEN@github.com/user/repo.git
    
    # Simple replacement for standard GitHub SSH URLs
    ORIGIN_REPO=$(echo "$ORIGIN_REPO" | sed -E "s|git@github.com:|https://x-access-token:$GITHUB_TOKEN@github.com/|")
    DEST_REPO=$(echo "$DEST_REPO" | sed -E "s|git@github.com:|https://x-access-token:$GITHUB_TOKEN@github.com/|")
    
    # Also configure git globally for this run to use the token for any other operations (like lfs)
    git config --global credential.helper store
    echo "https://x-access-token:$GITHUB_TOKEN@github.com" > ~/.git-credentials
fi

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

# Run transformations on every branch
# Get list of all local branches
# We use 'git for-each-ref' to get a clean list of refs/heads/
BRANCHES=$(git for-each-ref --format='%(refname:short)' refs/heads/)

for BRANCH in $BRANCHES; do
    echo "Processing branch: $BRANCH"
    git checkout "$BRANCH"

    # Run Moderne CLI transformations
    rm $HOME/.moderne/cli/maven-cache.cache 2>/dev/null || true
    
    echo "Workspace files:"
    echo "$(ls -la ../)"
    echo "$(ls -la .)"
    echo "Recipes to run:"
    cat "../recipes.conf"
    
    if [ -f "../recipes.conf" ]; then
        # Create a transformation branch
        TRANSFORMATION_BRANCH="moderne/transformation-$BRANCH"
        echo "Creating transformation branch: $TRANSFORMATION_BRANCH"
        git checkout -b "$TRANSFORMATION_BRANCH"
    
        echo "Applying recipes from recipes.conf..."
        while IFS= read -r recipe_cmd || [ -n "$recipe_cmd" ]; do
            # build the latest LST before applying the recipe
            echo "Building LSTs..."
            mod build .
    
            # Skip empty lines and comments
            [[ -z "$recipe_cmd" || "$recipe_cmd" =~ ^# ]] && continue
            
            echo "Running recipe: $recipe_cmd"
            eval "mod run . --recipe $recipe_cmd"
    
            # Apply changes and add to index
            mod git apply . --last-recipe-run
            mod git add . --last-recipe-run
            
            # Commit passing the recipe as the message (if there are changes)
            if ! git diff --cached --quiet; then
                 mod git commit . --last-recipe-run -m "Applied recipe: $recipe_cmd"
            else
                 echo "No changes result from recipe: $recipe_cmd"
            fi
        done < "../recipes.conf"
        
        # Return to original branch
        git checkout "$BRANCH"
        
        # Squash merge the transformation branch
        echo "Squash merging transformation branch..."
        git merge --squash "$TRANSFORMATION_BRANCH"
        
        # Delete the transformation branch so it doesn't get pushed
        echo "Deleting transformation branch..."
        git branch -D "$TRANSFORMATION_BRANCH"
        
    else
        echo "No recipes.conf found, skipping transformations."
    fi
    
    # Remove the trigger workflow from the destination to avoid pollution
    if [ -f ".github/workflows/trigger-sync.yml" ]; then
        echo "Removing trigger-sync.yml from destination..."
        git rm ".github/workflows/trigger-sync.yml"
    fi
    
    echo "Committing the following changes on $BRANCH:"
    git status
    
    # Commit the squash merge (and potentially the workflow deletion)
    # We check if there are changes to commit to avoid empty commit errors if recipes did nothing
    if ! git diff --cached --quiet; then
        git commit -m "Apply Moderne transformations"
    else
        echo "No changes to commit for branch $BRANCH."
    fi

done

# Push to destination
echo "Pushing to destination..."
git remote add dest "$DEST_REPO"
git push dest --all --force
git push dest --tags --force

if git lfs version >/dev/null 2>&1; then
    git lfs push dest --all
fi

echo "Sync complete."
