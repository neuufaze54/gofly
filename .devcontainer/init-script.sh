#!/bin/bash
set -e
LOG_FILE="/workspaces/gofly/init-script.log"
echo "Starting init-script.sh at $(date)" | tee -a $LOG_FILE
# Check if container is running
if docker ps -q -f name=agitated_cannon | grep -q .; then
    echo "Container agitated_cannon is already running" | tee -a $LOG_FILE
elif [ -f "/workspaces/gofly/start-docker.log" ] && grep -q "start-docker.sh completed successfully" /workspaces/gofly/start-docker.log; then
    echo "start-docker.sh previously executed successfully, but container is not running. Restarting..." | tee -a $LOG_FILE
    bash /workspaces/gofly/.devcontainer/start-docker.sh >> $LOG_FILE 2>&1
    if [ $? -eq 0 ]; then
        echo "start-docker.sh executed successfully" | tee -a $LOG_FILE
    else
        echo "Error: start-docker.sh failed" | tee -a $LOG_FILE
        exit 1
    fi
else
    echo "Running start-docker.sh..." | tee -a $LOG_FILE
    bash /workspaces/gofly/.devcontainer/start-docker.sh >> $LOG_FILE 2>&1
    if [ $? -eq 0 ]; then
        echo "start-docker.sh executed successfully" | tee -a $LOG_FILE
    else
        echo "Error: start-docker.sh failed" | tee -a $LOG_FILE
        exit 1
    fi
fi
echo "init-script.sh completed successfully at $(date)" | tee -a $LOG_FILE
