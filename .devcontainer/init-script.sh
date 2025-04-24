#!/bin/bash
set -e
LOG_FILE="/workspaces/gofly/init-script.log"
echo "Starting init-script.sh at $(date)" | tee -a $LOG_FILE
if [ -f "/workspaces/gofly/start-docker.log" ] && grep -q "start-docker.sh completed successfully" /workspaces/gofly/start-docker.log; then
    echo "start-docker.sh already executed successfully" | tee -a $LOG_FILE
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
