# Moderne Repository Sync Action

This action provides an automated way to synchronize a GitHub repository to a destination repository while applying code transformations using the Moderne CLI. It ensures the destination repository's history mirrors the origin's, with specific code modifications applied on top.

## How It Works

The sync process follows these steps:
1.  **Clone**: Clones the source (origin) repository.
2.  **LFS**: Pulls Git LFS objects if applicable.
3.  **Normalize**: Applies configured Moderne recipes (OpenRewrite) to the codebase.
4.  **Commit**: Creates a new commit with the applied transformations.
5.  **Force Push**: Pushes the entire history to the destination repository, overwriting it to match the origin + transformations.

## Recipe Configuration

The action supports two levels of recipe configuration, allowing for both global standards and repository-specific needs.

### 1. Global Recipes
Global recipes are defined in the sync workflow (`run-sync.yml`) or passed via the `global_recipes` input. These transformations are applied to **every** repository that uses this sync action.

**Use Case**:
-   Swapping internal domain names for external ones (e.g., `origindomain.com` -> `destdomain.com`).
-   Standardizing infrastructure configuration (e.g., AWS regions).

### 2. Repository-Specific Recipes
Additional recipes can be specified by the origin repository when triggering the sync. these are passed in the `client_payload` of the `repository_dispatch` event.

**Use Case**:
-   Applying unit test best practices (JUnit 5, AssertJ) specific to a Java project.
-   Running static analysis fixes relevant to the specific codebase.

## Usage

### Triggering a Sync
The sync is typically triggered automatically by a workflow in the origin repository:

```yaml
- name: Trigger Sync Workflow
  uses: peter-evans/repository-dispatch@v2
  with:
    event-type: sync-trigger
    client-payload: |
      {
        "origin_repo": "...",
        "destination_repo": "...",
        "recipes": ["org.openrewrite.java.cleanup.CommonStaticAnalysis"]
      }
```

### Manual Run
You can also manually run the sync via the GitHub Actions "Run workflow" button, optionally overriding the global recipes.

## Verification

To evaluate the results of the sync:

1.  Navigate to the **Destination Repository** on GitHub.
2.  Click on the **Insights** tab.
3.  Select **Network** from the left sidebar.
4.  **Verify History**: You should see that the destination branch (e.g., `main`) shares the same git history as the origin, with the addition of the "Apply Moderne transformations" commit(s) at the tip.

 This view confirms that the sync is maintaining history fidelity while successfully applying your code mods.
