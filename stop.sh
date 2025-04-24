#!/bin/bash
set -e
# Check if gh is installed
if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI (gh) not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y gh
    if [ $? -ne 0 ]; then
        echo "Failed to install GitHub CLI."
        exit 1
    fi
    echo "GitHub CLI installed successfully."
fi
# Get repository details
REPO=$(git config --get remote.origin.url | sed 's/.*github.com\///' | sed 's/.git$//')
if [ -z "$REPO" ]; then
    echo "Failed to detect repository."
    exit 1
fi
echo "Detected repository: $REPO"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Current branch: $BRANCH"
# Get Codespace name
CODESPACE_NAME=$(gh codespace list --json name,state,repository | jq -r '.[] | select(.state == "Running" and .repository == "kouboujou22/gofly") | .name')
if [ -z "$CODESPACE_NAME" ]; then
    echo "No running Codespace found for repository $REPO."
    exit 1
fi
echo "Found Codespace: $CODESPACE_NAME"
# Stop any running container
if docker ps -q -f name=agitated_cannon | grep -q .; then
    echo "Stopping container agitated_cannon..."
    docker stop agitated_cannon
    docker rm agitated_cannon
fi
# Reset start-docker.log to force restart
echo "Resetting start-docker.log..."
rm -f /workspaces/gofly/start-docker.log
# Stop Codespace
echo "Stopping Codespace $CODESPACE_NAME..."
gh codespace stop -c "$CODESPACE_NAME"
if [ $? -ne 0 ]; then
    echo "Failed to stop Codespace $CODESPACE_NAME."
    exit 1
fi
echo "Codespace $CODESPACE_NAME stopped successfully."
# Schedule restart via GitHub Actions
echo "Scheduling restart for Codespace $CODESPACE_NAME..."
gh api -X POST \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "/repos/$REPO/dispatches" \
    -f event_type=restart-codespace \
    -f "client_payload[codespace_name]=$CODESPACE_NAME"
if [ $? -ne 0 ]; then
    echo "Failed to dispatch restart workflow."
    exit 1
fi
echo "Restart workflow dispatched successfully."
