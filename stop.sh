#!/bin/bash

# Script to stop the current GitHub Codespace where the script is running

# Step 0: Install GitHub CLI (gh) if it's not installed
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) not found. Installing..."

    # Add GitHub CLI's official key and repo, then install it
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
        sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
        sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
        sudo apt update && \
        sudo apt install gh -y

    if ! command -v gh &> /dev/null; then
        echo "Error: GitHub CLI installation failed."
        exit 1
    fi

    echo "GitHub CLI installed successfully."
fi

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo "Error: Not inside a git repository. Cannot determine the Codespace repository."
    exit 1
fi

# Get the repository name in owner/repo format (e.g., rouhanaom45/chain)
REPO=$(git config --get remote.origin.url | sed -E 's|.*[:/]([^/]+)/([^/]+)(\.git)?$|\1/\2|')
if [ -z "$REPO" ]; then
    echo "Error: Could not determine repository name from remote.origin.url"
    exit 1
fi
echo "Detected repository: $REPO"

# Get the current branch name
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ -z "$CURRENT_BRANCH" ]; then
    echo "Error: Could not determine current branch"
    exit 1
fi
echo "Current branch: $CURRENT_BRANCH"

# Get the list of Codespaces
CODESPACES=$(gh codespace list)
if [ -z "$CODESPACES" ]; then
    echo "Error: No Codespaces found or authentication failed."
    echo "Try unsetting GITHUB_TOKEN and re-authenticating:"
    echo "  unset GITHUB_TOKEN"
    echo "  gh auth login"
    echo "Select 'github.com', 'HTTPS', browser authentication, and ensure 'codespace' scope is selected."
    exit 1
fi

# Find the Codespace matching the repository and branch with active branch (e.g., main*)
CODESPACE_NAME=$(echo "$CODESPACES" | grep "$REPO" | grep "${CURRENT_BRANCH}\*" | awk '{print $1}' | head -n 1)
if [ -z "$CODESPACE_NAME" ]; then
    echo "Error: No active Codespace found for repository $REPO and branch $CURRENT_BRANCH (expected branch with '*')"
    echo "Codespace list output:"
    echo "$CODESPACES"
    echo "Please verify you're running the script in the correct Codespace."
    exit 1
fi
echo "Found Codespace: $CODESPACE_NAME"

# Stop the Codespace
echo "Stopping Codespace $CODESPACE_NAME..."
STOP_OUTPUT=$(gh codespace stop -c "$CODESPACE_NAME" 2>&1)
STOP_EXIT_CODE=$?

if [ $STOP_EXIT_CODE -eq 0 ]; then
    echo "Codespace $CODESPACE_NAME stopped successfully."
else
    echo "Error: Failed to stop Codespace $CODESPACE_NAME"
    echo "Error details: $STOP_OUTPUT"
    if echo "$STOP_OUTPUT" | grep -q "HTTP 403"; then
        echo "Reason: HTTP 403 Forbidden - likely due to insufficient token permissions."
        echo "Try unsetting GITHUB_TOKEN and re-authenticating:"
        echo "  unset GITHUB_TOKEN"
        echo "  gh auth logout"
        echo "  gh auth login"
        echo "Select 'github.com', 'HTTPS', browser authentication, and ensure 'codespace' scope is selected."
        echo "Alternatively, create a token at https://github.com/settings/tokens with 'codespace' and 'repo' scopes, then run:"
        echo "  gh auth login --with-token"
    fi
    exit 1
fi
