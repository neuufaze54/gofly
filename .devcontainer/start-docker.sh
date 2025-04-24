#!/bin/bash

# Script to start Docker container on Codespace startup
LOG_FILE="/workspaces/gofly/start-docker.log"
echo "start-docker.sh started at $(date)" > "$LOG_FILE"

# Check if the container exists (running or stopped)
if docker ps -a -q -f name=agitated_cannon | grep -q .; then
    echo "Container agitated_cannon exists." >> "$LOG_FILE"
    # Check if the container is running
    if docker ps -q -f name=agitated_cannon | grep -q .; then
        echo "Docker container agitated_cannon is already running." | tee -a "$LOG_FILE"
        # Verify that the VNC service is accessible
        if nc -zv 127.0.0.1 6200 2>&1 | grep -q "open"; then
            echo "VNC service is accessible on port 6200." | tee -a "$LOG_FILE"
            echo "start-docker.sh completed successfully" >> "$LOG_FILE"
            exit 0
        else
            echo "Error: VNC service is not accessible on port 6200 despite container running." | tee -a "$LOG_FILE"
            docker logs agitated_cannon >> "$LOG_FILE" 2>&1
            # Remove the container to recreate it fresh
            echo "Removing container agitated_cannon to recreate it..." | tee -a "$LOG_FILE"
            docker stop agitated_cannon >> "$LOG_FILE" 2>&1
            docker rm agitated_cannon >> "$LOG_FILE" 2>&1
        fi
    else
        # Container exists but is stopped; remove it to recreate fresh
        echo "Removing stopped Docker container agitated_cannon..." | tee -a "$LOG_FILE"
        docker rm agitated_cannon >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            echo "Stopped container agitated_cannon removed successfully." | tee -a "$LOG_FILE"
        else
            echo "Error: Failed to remove stopped Docker container agitated_cannon." | tee -a "$LOG_FILE"
            exit 1
        fi
    fi
fi

# Container doesn't exist; create and run it
echo "Starting new Docker container agitated_cannon..." | tee -a "$LOG_FILE"
docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu dorowu/ubuntu-desktop-lxde-vnc >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "Docker container agitated_cannon started successfully." | tee -a "$LOG_FILE"
    # Wait for the container to fully start and verify VNC service
    sleep 5
    if nc -zv 127.0.0.1 6200 2>&1 | grep -q "open"; then
        echo "VNC service is accessible on port 6200." | tee -a "$LOG_FILE"
        # Ensure Desktop directory exists
        echo "Ensuring /home/ubuntu/Desktop exists in the container..." | tee -a "$LOG_FILE"
        docker exec agitated_cannon bash -c "mkdir -p /home/ubuntu/Desktop && chown ubuntu:ubuntu /home/ubuntu/Desktop" >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            echo "Desktop directory created or verified successfully." | tee -a "$LOG_FILE"
        else
            echo "Error: Failed to create or verify Desktop directory." | tee -a "$LOG_FILE"
            docker exec agitated_cannon ls -ld /home/ubuntu >> "$LOG_FILE" 2>&1
            exit 1
        fi
        # Create mohamed.txt on the container's desktop
        echo "Creating mohamed.txt on the container's desktop..." | tee -a "$LOG_FILE"
        docker exec agitated_cannon bash -c "echo 'hello' > /home/ubuntu/Desktop/mohamed.txt && chown ubuntu:ubuntu /home/ubuntu/Desktop/mohamed.txt" >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            echo "mohamed.txt created successfully on the desktop." | tee -a "$LOG_FILE"
            # Verify file contents
            FILE_CONTENT=$(docker exec agitated_cannon cat /home/ubuntu/Desktop/mohamed.txt 2>/dev/null)
            if [ "$FILE_CONTENT" = "hello" ]; then
                echo "mohamed.txt contains expected content: 'hello'." | tee -a "$LOG_FILE"
            else
                echo "Error: mohamed.txt does not contain expected content. Content: '$FILE_CONTENT'" | tee -a "$LOG_FILE"
                exit 1
            fi
        else
            echo "Error: Failed to create mohamed.txt on the desktop." | tee -a "$LOG_FILE"
            docker exec agitated_cannon ls -l /home/ubuntu/Desktop >> "$LOG_FILE" 2>&1
            exit 1
        fi
        echo "start-docker.sh completed successfully" >> "$LOG_FILE"
    else
        echo "Error: VNC service is not accessible on port 6200 after starting container." | tee -a "$LOG_FILE"
        docker logs agitated_cannon >> "$LOG_FILE" 2>&1
        exit 1
    fi
else
    echo "Error: Failed to start Docker container agitated_cannon." | tee -a "$LOG_FILE"
    docker logs agitated_cannon >> "$LOG_FILE" 2>&1
    exit 1
fi
