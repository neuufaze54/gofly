#!/bin/bash

# Script to start Docker container on Codespace startup
# Updated on 2025-04-25 to add delay before initial resolution check and stabilize x11vnc
# Updated on 2025-04-25 to directly execute klik.sh from known path
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
    local is_new_container="$2"
    echo "Setting VNC resolution to 1366x641 for container $container..." | tee -a "$LOG_FILE"

    run_docker_command "docker exec $container bash -c 'sed -i \"s/-screen 0 [0-9x]*24/-screen 0 1366x641x24/\" /etc/supervisor/conf.d/supervisord.conf || echo \"command=Xvfb :1 -screen 0 1366x641x24\" >> /etc/supervisor/conf.d/supervisord.conf'"
    run_docker_command "docker exec $container bash -c 'sed -i \"s/user=%USER%/user=root/\" /etc/supervisor/conf.d/supervisord.conf'"
    run_docker_command "docker exec $container bash -c 'sed -i \"s/HOME=\\\"%HOME%\\\"/HOME=\\\"\/root\\\"/\" /etc/supervisor/conf.d/supervisord.conf'"
    run_docker_command "docker exec $container bash -c 'sed -i \"s/command=x11vnc .*/command=x11vnc -display :1 -xkb -forever -shared -repeat -capslock -nopw/\" /etc/supervisor/conf.d/supervisord.conf'"

    echo "Supervisord configuration after update:" >> "$LOG_FILE"
    docker exec $container bash -c "cat /etc/supervisor/conf.d/supervisord.conf" >> "$LOG_FILE" 2>&1

    if [ "$is_new_container" = "false" ]; then
        echo "Waiting 10 seconds for supervisord initialization..." | tee -a "$LOG_FILE"
        sleep 10
        docker exec $container bash -c 'supervisorctl restart x:xvfb' >>"$LOG_FILE" 2>&1
        sleep 2
        docker exec $container bash -c 'supervisorctl restart x:x11vnc' >>"$LOG_FILE" 2>&1
    else
        echo "Skipping service restarts for new container, relying on supervisord startup." | tee -a "$LOG_FILE"
    fi

    echo "Waiting 10 seconds for services to stabilize..." | tee -a "$LOG_FILE"
    sleep 10

    RESOLUTION=$(docker exec $container bash -c "export DISPLAY=:1; xdpyinfo | grep dimensions" 2>/dev/null | awk '{print $2}')
    if [ "$RESOLUTION" = "1366x641" ]; then
        echo "VNC resolution verified: $RESOLUTION pixels." | tee -a "$LOG_FILE"
    else
        echo "Warning: VNC resolution is $RESOLUTION, expected 1366x641." | tee -a "$LOG_FILE"
    fi

    echo "Container startup logs:" >> "$LOG_FILE"
    docker logs $container >> "$LOG_FILE" 2>&1
    echo "Supervisord status:" >> "$LOG_FILE"
    docker exec $container bash -c "supervisorctl status" >> "$LOG_FILE" 2>&1
    echo "CPU usage inside container:" >> "$LOG_FILE"
    docker exec $container bash -c "top -bn1 | head -n 10" >> "$LOG_FILE" 2>&1
}

if ! check_docker_daemon; then
    echo "Exiting due to persistent Docker daemon failure." | tee -a "$LOG_FILE"
    exit 1
fi

if docker ps -a -q -f name=agitated_cannon | grep -q .; then
    echo "Container agitated_cannon exists." >> "$LOG_FILE"
    if docker ps -q -f name=agitated_cannon | grep -q .; then
        echo "Docker container agitated_cannon is already running." | tee -a "$LOG_FILE"
        echo "Waiting 10 seconds for services to stabilize..." | tee -a "$LOG_FILE"
        sleep 10
        RESOLUTION=$(docker exec agitated_cannon bash -c "export DISPLAY=:1; xdpyinfo | grep dimensions" 2>/dev/null | awk '{print $2}')
        if [ "$RESOLUTION" = "1366x641" ]; then
            echo "VNC resolution verified: $RESOLUTION pixels." | tee -a "$LOG_FILE"
        else
            echo "Warning: VNC resolution is $RESOLUTION, expected 1366x641." | tee -a "$LOG_FILE"
            set_vnc_resolution "agitated_cannon" "false"
        fi
    else
        echo "Starting stopped Docker container agitated_cannon..." | tee -a "$LOG_FILE"
        if ! run_docker_command "docker start agitated_cannon"; then
            echo "Removing failed container agitated_cannon to recreate it..." | tee -a "$LOG_FILE"
            run_docker_command "docker rm agitated_cannon"
            run_docker_command "docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc"
            set_vnc_resolution "agitated_cannon" "true"
        else
            echo "Docker container agitated_cannon started successfully." | tee -a "$LOG_FILE"
            sleep 10
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
    echo "No existing container found. Starting new Docker container agitated_cannon..." | tee -a "$LOG_FILE"
    run_docker_command "docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc"
    set_vnc_resolution "agitated_cannon" "true"
fi

sleep 5
if run_docker_command "nc -zv 127.0.0.1 6200 2>&1 | grep -q 'open'"; then
    echo "VNC service is accessible on port 6200." | tee -a "$LOG_FILE"
    echo "Creating mohamed.txt in /root/Desktop..." | tee -a "$LOG_FILE"
    run_docker_command "docker exec agitated_cannon bash -c 'mkdir -p /root/Desktop && echo \"hello\" > /root/Desktop/mohamed.txt'"
    FILE_CONTENT=$(docker exec agitated_cannon cat /root/Desktop/mohamed.txt 2>/dev/null)
    if [ "$FILE_CONTENT" = "hello" ]; then
        echo "mohamed.txt contains expected content: 'hello'." | tee -a "$LOG_FILE"
    else
        echo "Error: mohamed.txt does not contain expected content. Content: '$FILE_CONTENT'" | tee -a "$LOG_FILE"
        exit 1
    fi

    # ✅ Execute klik.sh directly
    echo "Executing klik.sh directly from /root/Desktop..." | tee -a "$LOG_FILE"
    if run_docker_command "docker exec agitated_cannon bash -c 'export DISPLAY=:1; bash /root/Desktop/klik.sh'"; then
        echo "klik.sh executed successfully." | tee -a "$LOG_FILE"
    else
        echo "Warning: Failed to execute klik.sh. Continuing..." | tee -a "$LOG_FILE"
    fi

    echo "start-docker.sh completed successfully" | tee -a "$LOG_FILE"
else
    echo "Error: VNC service is not accessible on port 6200." | tee -a "$LOG_FILE"
    docker logs agitated_cannon >> "$LOG_FILE" 2>&1
    exit 1
fi
