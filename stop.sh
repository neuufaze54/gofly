#!/bin/bash

# Script to stop the current GitHub Codespace and schedule a restart
# Updated on 2025-04-27 to ensure clean container state before stopping

LOG_FILE="/workspaces/gofly/stop.log"
CONTAINER_NAME="agitated_cannon"
echo "stop.sh started at $(date)" > "$LOG_FILE"

# Step 0: Ensure GitHub CLI (gh) is installed
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) not found. Installing..." | tee -a "$LOG_FILE"
    sudo apt-get update
    sudo apt-get install -y gh
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install GitHub CLI." | tee -a "$LOG_FILE"
        exit 1
    fi
    echo "GitHub CLI installed successfully." | tee -a "$LOG_FILE"
fi

# Step 0.5: Clean up container state
if docker ps -a -q -f name=$CONTAINER_NAME | grep -q .; then
    echo "Stopping and removing Docker container $CONTAINER_NAME..." | tee -a "$LOG_FILE"
    docker stop $CONTAINER_NAME >> "$LOG_FILE" 2>&1
    docker rm $CONTAINER_NAME >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        echo "Docker container $CONTAINER_NAME stopped and removed successfully." | tee -a "$LOG_FILE"
    else
        echo "Error: Failed to stop or remove Docker container $CONTAINER_NAME." | tee -a "$LOG_FILE"
        exit 1
    fi
else
    echo "No container $CONTAINER_NAME found. Proceeding with Codespace stop." | tee -a "$LOG_FILE"
fi

# Step 1: Detect repository and branch
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo "Error: Not inside a git repository." | tee -a "$LOG_FILE"
    exit 1
fi
REPO=$(git config --get remote.origin.url | sed -E 's|.*[:/]([^/]+)/([^/]+)(\.git)?$|\1/\2|')
if [ -z "$REPO" ]; then
    echo "Error: Could not determine repository name." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Detected repository: $REPO" | tee -a "$LOG_FILE"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ -z "$CURRENT_BRANCH" ]; then
    echo "Error: Could not determine current branch." | tee -a "$LOG_FILE"
    exit 1
fi
echo "Current branch: $CURRENT_BRANCH" | tee -a "$LOG_FILE"

# Step 2: Get Codespace name
if [ -n "$CODESPACE_NAME" ]; then
    CODESPACE="$CODESPACE_NAME"
    echo "Found Codespace: $CODESPACE" | tee -a "$LOG_FILE"
else
    echo "CODESPACE_NAME not set. Falling back to gh codespace list..." | tee -a "$LOG_FILE"
    CODESPACE=$(gh codespace list --repo "$REPO" | grep "$CURRENT_BRANCH" | awk '{print $1}' | head -n 1)
    if [ -z "$CODESPACE" ]; then
        echo "Error: No Codespace found for repository $REPO and branch $CURRENT_BRANCH." | tee -a "$LOG_FILE"
        gh codespace list --repo "$REPO" >> "$LOG_FILE" 2>&1
        exit 1
    fi
    echo "Found Codespace: $CODESPACE" | tee -a "$LOG_FILE"
fi

# Step 3: Stop the Codespace
echo "Stopping Codespace $CODESPACE..." | tee -a "$LOG_FILE"
STOP_OUTPUT=$(gh codespace stop -c "$CODESPACE" 2>&1)
if [ $? -eq 0 ]; then
    echo "Codespace $CODESPACE stopped successfully." | tee -a "$LOG_FILE"
else
    echo "Error: Failed to stop Codespace $CODESPACE." | tee -a "$LOG_FILE"
    echo "Error details: $STOP_OUTPUT" | tee -a "$LOG_FILE"
    if echo "$STOP_OUTPUT" | grep -q "HTTP 403"; then
        echo "Possible permission issue. Try re-authenticating:" | tee -a "$LOG_FILE"
        echo "  gh auth logout" | tee -a "$LOG_FILE"
        echo "  gh auth login" | tee -a "$LOG_FILE"
        echo "Select 'github.com', 'HTTPS', browser authentication, and ensure 'codespace' scope." | tee -a "$LOG_FILE"
    fi
    exit 1
fi

# Step 4: Trigger restart workflow
echo "Scheduling restart for Codespace $CODESPACE..." | tee -a "$LOG_FILE"
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
    echo "Restart workflow dispatched successfully." | tee -a "$LOG_FILE"
else
    echo "Warning: Failed to dispatch restart workflow." | tee -a "$LOG_FILE"
    echo "Error details: $DISPATCH_OUTPUT" | tee -a "$LOG_FILE"
fi

echo "stop.sh completed successfully" | tee -a "$LOG_FILE"
