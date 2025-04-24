#!/bin/bash

# Script to stop the current GitHub Codespace and schedule a restart

# Step 0: Ensure GitHub CLI (gh) is installed
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y gh
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install GitHub CLI."
        exit 1
    fi
    echo "GitHub CLI installed successfully."
fi

# Step 0.5: Stop and remove the agitated_cannon container
if docker ps -q -f name=agitated_cannon | grep -q .; then
    echo "Stopping Docker container agitated_cannon..."
    docker stop agitated_cannon
    if [ $? -eq 0 ]; then
        echo "Docker container agitated_cannon stopped successfully."
    else
        echo "Error: Failed to stop Docker container agitated_cannon."
        exit 1
    fi
fi
if docker ps -a -q -f name=agitated_cannon | grep -q .; then
    echo "Removing Docker container agitated_cannon..."
    docker rm agitated_cannon
    if [ $? -eq 0 ]; then
        echo "Docker container agitated_cannon removed successfully."
    else
        echo "Error: Failed to remove Docker container agitated_cannon."
        exit 1
    fi
fi

# Step 1: Detect repository and branch
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo "Error: Not inside a git repository."
    exit 1
fi
REPO=$(git config --get remote.origin.url | sed -E 's|.*[:/]([^/]+)/([^/]+)(\.git)?$|\1/\2|')
if [ -z "$REPO" ]; then
    echo "Error: Could not determine repository name."
    exit 1
fi
echo "Detected repository: $REPO"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ -z "$CURRENT_BRANCH" ]; then
    echo "Error: Could not determine current branch."
    exit 1
fi
echo "Current branch: $CURRENT_BRANCH"

# Step 2: Get Codespace name
if [ -n "$CODESPACE_NAME" ]; then
    CODESPACE="$CODESPACE_NAME"
    echo "Found Codespace: $CODESPACE"
else
    echo "CODESPACE_NAME not set. Falling back to gh codespace list..."
    CODESPACE=$(gh codespace list --repo "$REPO" | grep "$CURRENT_BRANCH" | awk '{print $1}' | head -n 1)
    if [ -z "$CODESPACE" ]; then
        echo "Error: No Codespace found for repository $REPO and branch $CURRENT_BRANCH."
        echo "Codespace list output:"
        gh codespace list --repo "$REPO"
        exit 1
    fi
    echo "Found Codespace: $CODESPACE"
fi

# Step 3: Stop the Codespace
echo "Stopping Codespace $CODESPACE..."
STOP_OUTPUT=$(gh codespace stop -c "$CODESPACE" 2>&1)
if [ $? -eq 0 ]; then
    echo "Codespace $CODESPACE stopped successfully."
else
    echo "Error: Failed to stop Codespace $CODESPACE."
    echo "Error details: $STOP_OUTPUT"
    if echo "$STOP_OUTPUT" | grep -q "HTTP 403"; then
        echo "Possible permission issue. Try re-authenticating:"
        echo "  gh auth logout"
        echo "  gh auth login"
        echo "Select 'github.com', 'HTTPS', browser authentication, and ensure 'codespace' scope."
    fi
    exit 1
fi

# Step 4: Trigger restart workflow
echo "Scheduling restart for Codespace $CODESPACE..."
# Create temporary JSON file for payload
TEMP_PAYLOAD=$(mktemp)
cat << EOF > "$TEMP_PAYLOAD"
{
  "event_type": "restart-codespace",
  "client_payload": {
    "codespace_name": "$CODESPACE"
  }
}
EOF
DISPATCH_OUTPUT=$(gh api -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  /repos/$REPO/dispatches \
  --input "$TEMP_PAYLOAD" 2>&1)
DISPATCH_STATUS=$?
rm -f "$TEMP_PAYLOAD"
if [ $DISPATCH_STATUS -eq 0 ]; then
    echo "Restart workflow dispatched successfully."
else
    echo "Warning: Failed to dispatch restart workflow."
    echo "Error details: $DISPATCH_OUTPUT"
fi
