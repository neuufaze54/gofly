#!/bin/bash

# Script to start Docker container on Codespace startup
# Updated on 2025-04-25 to add delay before initial resolution check and stabilize x11vnc
# Updated on 2025-04-25 to execute klik.sh with DISPLAY=:1 if found
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
        if bash -c "$cmd" >>"$LOG_FILE" 2>&1; then
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

# Function to set and verify VNC resolution
set_vnc_resolution() {
    local container="$1"
    local is_new_container="$2"  # "true" for new containers, "false" for existing
    echo "Setting VNC resolution to 1366x641 for container $container..." | tee -a "$LOG_FILE"
    # Update supervisord configuration for xvfb
    if run_docker_command "docker exec $container bash -c 'sed -i \"s/-screen 0 [0-9x]*24/-screen 0 1366x641x24/\" /etc/supervisor/conf.d/supervisord.conf || echo \"command=Xvfb :1 -screen 0 1366x641x24\" >> /etc/supervisor/conf.d/supervisord.conf'"; then
        echo "Updated supervisord configuration for Xvfb resolution 1366x641." | tee -a "$LOG_FILE"
    else
        echo "Warning: Failed to update supervisord configuration for Xvfb. Continuing..." | tee -a "$LOG_FILE"
    fi
    # Fix %USER% and %HOME% in lxpanel and pcmanfm
    if run_docker_command "docker exec $container bash -c 'sed -i \"s/user=%USER%/user=root/\" /etc/supervisor/conf.d/supervisord.conf'"; then
        echo "Fixed %USER% in supervisord configuration." | tee -a "$LOG_FILE"
    else
        echo "Warning: Failed to fix %USER% in supervisord configuration. Continuing..." | tee -a "$LOG_FILE"
    fi
    if run_docker_command "docker exec $container bash -c 'sed -i \"s/HOME=\\\"%HOME%\\\"/HOME=\\\"\/root\\\"/\" /etc/supervisor/conf.d/supervisord.conf'"; then
        echo "Fixed %HOME% in supervisord configuration." | tee -a "$LOG_FILE"
    else
        echo "Warning: Failed to fix %HOME% in supervisord configuration. Continuing..." | tee -a "$LOG_FILE"
    fi
    # Update x11vnc configuration to ensure stability
    if run_docker_command "docker exec $container bash -c 'sed -i \"s/command=x11vnc .*/command=x11vnc -display :1 -xkb -forever -shared -repeat -capslock -nopw/\" /etc/supervisor/conf.d/supervisord.conf'"; then
        echo "Updated x11vnc configuration with -nopw." | tee -a "$LOG_FILE"
    else
        echo "Warning: Failed to update x11vnc configuration. Continuing..." | tee -a "$LOG_FILE"
    fi
    # Log supervisord configuration for debugging
    echo "Supervisord configuration after update:" >> "$LOG_FILE"
    docker exec $container bash -c "cat /etc/supervisor/conf.d/supervisord.conf" >> "$LOG_FILE" 2>&1
    # Restart services only for existing containers if needed
    if [ "$is_new_container" = "false" ]; then
        echo "Waiting 10 seconds for supervisord initialization..." | tee -a "$LOG_FILE"
        sleep 10
        if docker exec $container bash -c 'supervisorctl restart x:xvfb' >>"$LOG_FILE" 2>&1; then
            echo "Xvfb service restarted." | tee -a "$LOG_FILE"
        else
            echo "Warning: Failed to restart Xvfb service. Continuing..." | tee -a "$LOG_FILE"
        fi
        sleep 2
        if docker exec $container bash -c 'supervisorctl restart x:x11vnc' >>"$LOG_FILE" 2>&1; then
            echo "x11vnc service restarted." | tee -a "$LOG_FILE"
        else
            echo "Warning: Failed to restart x11vnc service. Continuing..." | tee -a "$LOG_FILE"
        fi
    else
        echo "Skipping service restarts for new container, relying on supervisord startup." | tee -a "$LOG_FILE"
    fi
    # Wait for services to stabilize
    echo "Waiting 10 seconds for services to stabilize..." | tee -a "$LOG_FILE"
    sleep 10
    # Verify resolution
    RESOLUTION=$(docker exec $container bash -c "export DISPLAY=:1; xdpyinfo | grep dimensions" 2>/dev/null | awk '{print $2}')
    if [ "$RESOLUTION" = "1366x641" ]; then
        echo "VNC resolution verified: $RESOLUTION pixels." | tee -a "$LOG_FILE"
    else
        echo "Warning: VNC resolution is $RESOLUTION, expected 1366x641." | tee -a "$LOG_FILE"
    fi
    # Log container startup for debugging
    echo "Container startup logs:" >> "$LOG_FILE"
    docker logs $container >> "$LOG_FILE" 2>&1
    # Log supervisord status
    echo "Supervisord status:" >> "$LOG_FILE"
    docker exec $container bash -c "supervisorctl status" >> "$LOG_FILE" 2>&1
    # Log CPU usage inside container
    echo "CPU usage inside container:" >> "$LOG_FILE"
    docker exec $container bash -c "top -bn1 | head -n 10" >> "$LOG_FILE" 2>&1
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
        # Wait for services to stabilize before verifying resolution
        echo "Waiting 10 seconds for services to stabilize..." | tee -a "$LOG_FILE"
        sleep 10
        # Verify resolution for existing containers
        echo "Verifying VNC resolution for existing container agitated_cannon..." | tee -a "$LOG_FILE"
        RESOLUTION=$(docker exec agitated_cannon bash -c "export DISPLAY=:1; xdpyinfo | grep dimensions" 2>/dev/null | awk '{print $2}')
        if [ "$RESOLUTION" = "1366x641" ]; then
            echo "VNC resolution verified: $RESOLUTION pixels." | tee -a "$LOG_FILE"
        else
            echo "Warning: VNC resolution is $RESOLUTION, expected 1366x641." | tee -a "$LOG_FILE"
            set_vnc_resolution "agitated_cannon" "false"
        fi
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
            if ! run_docker_command "docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc"; then
                echo "Error: Failed to start new Docker container agitated_cannon." | tee -a "$LOG_FILE"
                docker logs agitated_cannon >> "$LOG_FILE" 2>&1
                exit 1
            fi
            echo "Docker container agitated_cannon started successfully." | tee -a "$LOG_FILE"
            set_vnc_resolution "agitated_cannon" "true"
        else
            echo "Docker container agitated_cannon started successfully." | tee -a "$LOG_FILE"
            # Wait for services to stabilize before verifying resolution
            echo "Waiting 10 seconds for services to stabilize..." | tee -a "$LOG_FILE"
            sleep 10
            # Verify resolution for existing containers
            echo "Verifying VNC resolution for existing container agitated_cannon..." | tee -a "$LOG_FILE"
            RESOLUTION=$(docker exec agitated_cannon bash -c "export DISPLAY=:1; xdpyinfo | grep dimensions" 2>/dev/null | awk '{print $2}')
            if [ "$RESOLUTION" = "1366x641" ]; then
                echo "VNC resolution verified: $RESOLUTION pixels." | tee -a "$LOG_FILE"
            else
                echo "Warning: VNC resolution is $RESOLUTION, expected 1366x641." | tee -a "$LOG_FILE"
                set_vnc_resolution "agitated_cannon" "false"
            fi
        fi
    fi
else
    # Container doesn't exist; create and run it
    echo "No existing container found. Starting new Docker container agitated_cannon..." | tee -a "$LOG_FILE"
    echo "Listing all containers for debugging:" >> "$LOG_FILE"
    docker ps -a >> "$LOG_FILE" 2>&1
    if ! run_docker_command "docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc"; then
        echo "Error: Failed to start new Docker container agitated_cannon." | tee -a "$LOG_FILE"
        docker logs agitated_cannon >> "$LOG_FILE" 2>&1
        exit 1
    fi
    echo "Docker container agitated_cannon started successfully." | tee -a "$LOG_FILE"
    set_vnc_resolution "agitated_cannon" "true"
fi

# Wait for the container to fully start and verify VNC service
sleep 5
if run_docker_command "nc -zv 127.0.0.1 6200 2>&1 | grep -q 'open'"; then
    echo "VNC service is accessible on port 6200." | tee -a "$LOG_FILE"
    echo "VNC GUI should display at fixed 1366x641 resolution. If scaling occurs, append ?resize=off to the VNC URL (e.g., http://<codespace-url>:6200/?resize=off)." | tee -a "$LOG_FILE"
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
    # Search for and execute klik.sh
    echo "Searching for klik.sh in filesystem..." | tee -a "$LOG_FILE"
    if run_docker_command "docker exec agitated_cannon bash -c 'export DISPLAY=:1; SCRIPT=\$(find / -name klik.sh 2>/dev/null | head -n 1); if [ -n \"\$SCRIPT\" ]; then chmod +x \"\$SCRIPT\" && \"\$SCRIPT\"; else echo \"klik.sh not found\"; fi'"; then
        echo "klik.sh executed successfully or not found." | tee -a "$LOG_FILE"
    else
        echo "Warning: Failed to execute klik.sh. Continuing..." | tee -a "$LOG_FILE"
    fi
    echo "start-docker.sh completed successfully" | tee -a "$LOG_FILE"
else
    echo "Error: VNC service is not accessible on port 6200 after starting container." | tee -a "$LOG_FILE"
    docker logs agitated_cannon >> "$LOG_FILE" 2>&1
    # Attempt to restart the container
    echo "Attempting to restart container agitated_cannon..." | tee -a "$LOG_FILE"
    if run_docker_command "docker restart agitated_cannon"; then
        echo "Container agitated_cannon restarted successfully." | tee -a "$LOG_FILE"
        # Re-verify VNC service
        sleep 5
        if run_docker_command "nc -zv 127.0.0.1 6200 2>&1 | grep -q 'open'"; then
            echo "VNC service is now accessible on port 6200 after restart." | tee -a "$LOG_FILE"
            echo "Creating mohamed.txt in /root/Desktop after restart..." | tee -a "$LOG_FILE"
            if run_docker_command "docker exec agitated_cannon bash -c 'mkdir -p /root/Desktop && echo \"hello\" > /root/Desktop/mohamed.txt'"; then
                echo "mohamed.txt created successfully in /root/Desktop after restart." | tee -a "$LOG_FILE"
                # Verify file contents
                FILE_CONTENT=$(docker exec agitated_cannon cat /root/Desktop/mohamed.txt 2>/dev/null)
                if [ "$FILE_CONTENT" = "hello" ]; then
                    echo "mohamed.txt in /root/Desktop contains expected content: 'hello' after restart." | tee -a "$LOG_FILE"
                else
                    echo "Error: mohamed.txt in /root/Desktop does not contain expected content after restart. Content: '$FILE_CONTENT'" | tee -a "$LOG_FILE"
                    exit 1
                fi
            else
                echo "Error: Failed to create mohamed.txt in /root/Desktop after restart." | tee -a "$LOG_FILE"
                docker exec agitated_cannon ls -l /root/Desktop >> "$LOG_FILE" 2>&1
                exit 1
            fi
            # Search for and execute klik.sh after restart
            echo "Searching for klik.sh in filesystem after restart..." | tee -a "$LOG_FILE"
            if run_docker_command "docker exec agitated_cannon bash -c 'export DISPLAY=:1; SCRIPT=\$(find / -name klik.sh 2>/dev/null | head -n 1); if [ -n \"\$SCRIPT\" ]; then chmod +x \"\$SCRIPT\" && \"\$SCRIPT\"; else echo \"klik.sh not found\"; fi'"; then
                echo "klik.sh executed successfully or not found after restart." | tee -a "$LOG_FILE"
            else
                echo "Warning: Failed to execute klik.sh after restart. Continuing..." | tee -a "$LOG_FILE"
            fi
            echo "start-docker.sh completed successfully after restart" | tee -a "$LOG_FILE"
        else
            echo "Error: VNC service remains inaccessible on port 6200 after restart." | tee -a "$LOG_FILE"
            docker logs agitated_cannon >> "$LOG_FILE" 2>&1
            exit 1
        fi
    else
        echo "Error: Failed to restart container agitated_cannon." | tee -a "$LOG_FILE"
        docker logs agitated_cannon >> "$LOG_FILE" 2>&1
        exit 1
    fi
fi
