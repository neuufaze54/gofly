#!/bin/bash

# Script to start Docker container on Codespace startup
LOG_FILE="/workspaces/gofly/start-docker.log"
echo "start-docker.sh started at $(date)" > "$LOG_FILE"

# Function to check if Docker daemon is available
check_docker_daemon() {
    local max_attempts=10
    local attempt=1
    local delay=5

    while [ $attempt -le $max_attempts ]; do
        if docker info >/dev/null 2>&1; then
            echo "Docker daemon is available (attempt $attempt)." | tee -a "$LOG_FILE"
            return 0
        fi
        echo "Docker daemon not available (attempt $attempt/$max_attempts). Retrying in $delay seconds..." | tee -a "$LOG_FILE"
        sleep $delay
        attempt=$((attempt + 1))
    done

    echo "Error: Docker daemon not available after $max_attempts attempts." | tee -a "$LOG_FILE"
    return 1
}

# Function to run a Docker command with retries
run_docker_command() {
    local cmd="$1"
    local max_attempts=3
    local attempt=1
    local delay=5

    while [ $attempt -le $max_attempts ]; do
        if bash -c "$cmd" >/dev/null 2>>"$LOG_FILE"; then
            return 0
        fi
        echo "Docker command failed (attempt $attempt/$max_attempts): $cmd" | tee -a "$LOG_FILE"
        echo "Retrying in $delay seconds..." | tee -a "$LOG_FILE"
        sleep $delay
        attempt=$((attempt + 1))
    done

    echo "Error: Docker command failed after $max_attempts attempts: $cmd" | tee -a "$LOG_FILE"
    return 1
}

# Wait for Docker daemon to be available
if ! check_docker_daemon; then
    echo "Exiting due to persistent Docker daemon failure." | tee -a "$LOG_FILE"
    exit 1
fi

# Check if the container exists (running or stopped)
if docker ps -a -q -f name=agitated_cannon | grep -q .; then
    echo "Container agitated_cannon exists." >> "$LOG_FILE"
    # Check if the container is running
    if docker ps -q -f name=agitated_cannon | grep -q .; then
        echo "Docker container agitated_cannon is already running." | tee -a "$LOG_FILE"
    else
        # Container exists but is stopped; start it to preserve state
        echo "Starting stopped Docker container agitated_cannon..." | tee -a "$LOG_FILE"
        if ! run_docker_command "docker start agitated_cannon"; then
            echo "Error: Failed to start existing Docker container agitated_cannon." | tee -a "$LOG_FILE"
            # Remove the container and create a new one as a fallback
            echo "Removing failed container agitated_cannon to recreate it..." | tee -a "$LOG_FILE"
            run_docker_command "docker rm agitated_cannon"
            # Proceed to create a new container
            echo "Starting new Docker container agitated_cannon..." | tee -a "$LOG_FILE"
            if ! run_docker_command "docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu dorowu/ubuntu-desktop-lxde-vnc"; then
                echo "Error: Failed to start new Docker container agitated_cannon." | tee -a "$LOG_FILE"
                docker logs agitated_cannon >> "$LOG_FILE" 2>&1
                exit 1
            fi
            echo "Docker container agitated_cannon started successfully." | tee -a "$LOG_FILE"
        else
            echo "Docker container agitated_cannon started successfully." | tee -a "$LOG_FILE"
        fi
    fi
else
    # Container doesn't exist; create and run it
    echo "No existing container found. Starting new Docker container agitated_cannon..." | tee -a "$LOG_FILE"
    if ! run_docker_command "docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu dorowu/ubuntu-desktop-lxde-vnc"; then
        echo "Error: Failed to start new Docker container agitated_cannon." | tee -a "$LOG_FILE"
        docker logs agitated_cannon >> "$LOG_FILE" 2>&1
        exit 1
    fi
    echo "Docker container agitated_cannon started successfully." | tee -a "$LOG_FILE"
fi

# Wait for the container to fully start and verify VNC service
sleep 5
if run_docker_command "nc -zv 127.0.0.1 6200 2>&1 | grep -q 'open'"; then
    echo "VNC service is accessible on port 6200." | tee -a "$LOG_FILE"
    # Create mohamed.txt in /root/Desktop (VNC GUI desktop)
    echo "Creating mohamed.txt in /root/Desktop..." | tee -a "$LOG_FILE"
    if run_docker_command "docker exec agitated_cannon bash -c 'mkdir -p /root/Desktop && echo \"hello\" > /root/Desktop/mohamed.txt'"; then
        echo "mohamed.txt created successfully in /root/Desktop." | tee -a "$LOG_FILE"
        # Verify file contents
        FILE_CONTENT=$(docker exec agitated_cannon cat /root/Desktop/mohamed.txt 2>/dev/null)
        if [ "$FILE_CONTENT" = "hello" ]; then
            echo "mohamed.txt in /root/Desktop contains expected content: 'hello'." | tee -a "$LOG_FILE"
        else
            echo "Error: mohamed.txt in /root/Desktop does not contain expected content. Content: '$FILE_CONTENT'" | tee -a "$LOG_FILE"
            exit 1
        fi
    else
        echo "Error: Failed to create mohamed.txt in /root/Desktop." | tee -a "$LOG_FILE"
        docker exec agitated_cannon ls -l /root/Desktop >> "$LOG_FILE" 2>&1
        exit 1
    fi
    echo "start-docker.sh completed successfully" | tee -a "$LOG_FILE"
else
    echo "Error: VNC service is not accessible on port 6200 after starting container." | tee -a "$LOG_FILE"
    docker logs agitated_cannon >> "$LOG_FILE" 2>&1
    exit 1
fi
