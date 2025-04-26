#!/bin/bash

# Script to start Docker container on Codespace startup
# Updated on 2025-04-27 to improve service readiness, background process management, and restart reliability

LOG_FILE="/workspaces/gofly/start-docker.log"
SETUP_LOG="/workspaces/gofly/setup.log"
CONTAINER_NAME="agitated_cannon"
echo "start-docker.sh started at $(date)" > "$LOG_FILE"

# Function to check Docker daemon availability
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

# Function to run Docker commands with retries
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

# Function to verify supervisord readiness
verify_supervisord_ready() {
    local container="$1"
    local max_attempts=10
    local attempt=1
    local delay=5

    echo "Verifying supervisord is ready in container $container..." | tee -a "$LOG_FILE"
    while [ $attempt -le $max_attempts ]; do
        if docker exec $container bash -c "supervisorctl status" | grep -q "RUNNING"; then
            echo "Supervisord is ready (attempt $attempt)." | tee -a "$LOG_FILE"
            return 0
        fi
        echo "Supervisord not ready (attempt $attempt/$max_attempts). Retrying in $delay seconds..." | tee -a "$LOG_FILE"
        sleep $delay
        attempt=$((attempt + 1))
    done

    echo "Error: Supervisord not ready after $max_attempts attempts." | tee -a "$LOG_FILE"
    return 1
}

# Function to verify VNC resolution
verify_vnc_resolution() {
    local container="$1"
    local max_attempts=5
    local attempt=1
    local delay=5
    local resolution=""

    echo "Verifying VNC resolution for container $container..." | tee -a "$LOG_FILE"
    while [ $attempt -le $max_attempts ]; do
        resolution=$(docker exec $container bash -c "export DISPLAY=:1; xdpyinfo | grep dimensions" 2>/dev/null | awk '{print $2}')
        if [ "$resolution" = "1366x641" ]; then
            echo "VNC resolution verified: $resolution pixels (attempt $attempt)." | tee -a "$LOG_FILE"
            return 0
        fi
        echo "Resolution check failed (attempt $attempt/$max_attempts): got $resolution, expected 1366x641. Retrying in $delay seconds..." | tee -a "$LOG_FILE"
        sleep $delay
        attempt=$((attempt + 1))
    done

    echo "Error: VNC resolution is $resolution, expected 1366x641 after $max_attempts attempts." | tee -a "$LOG_FILE"
    return 1
}

# Function to set VNC resolution
set_vnc_resolution() {
    local container="$1"
    local is_new_container="$2"
    echo "Setting VNC resolution to 1366x641 for container $container..." | tee -a "$LOG_FILE"

    run_docker_command "docker exec $container bash -c 'sed -i \"s/-screen 0 [0-9x]*24/-screen 0 1366x641x24/\" /etc/supervisor/conf.d/supervisord.conf || echo \"command=Xvfb :1 -screen 0 1366x641x24\" >> /etc/supervisor/conf.d/supervisord.conf'"
    run_docker_command "docker exec $container bash -c 'sed -i \"s/user=%USER%/user=root/\" /etc/supervisor/conf.d/supervisord.conf'"
    run_docker_command "docker exec $container bash -c 'sed -i \"s/HOME=\\\"%HOME%\\\"/HOME=\\\"\/root\\\"/\" /etc/supervisor/conf.d/supervisord.conf'"
    run_docker_command "docker exec $container bash -c 'sed -i \"s/command=x11vnc .*/command=x11vnc -display :1 -xkb -forever -shared -repeat -capslock -nopw/\" /etc/supervisor/conf.d/supervisord.conf'"

    if [ "$is_new_container" = "false" ]; then
        verify_supervisord_ready "$container"
        run_docker_command "docker exec $container bash -c 'supervisorctl restart x:xvfb'" || echo "Warning: Failed to restart Xvfb service." | tee -a "$LOG_FILE"
        sleep 2
        run_docker_command "docker exec $container bash -c 'supervisorctl restart x:x11vnc'" || echo "Warning: Failed to restart x11vnc service." | tee -a "$LOG_FILE"
    fi

    sleep 10
    if ! verify_vnc_resolution "$container"; then
        echo "Error: Failed to verify VNC resolution. Recreating container..." | tee -a "$LOG_FILE"
        run_docker_command "docker rm -f $container"
        run_docker_command "docker run -d --name $container -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc"
        set_vnc_resolution "$container" "true"
        verify_vnc_resolution "$container" || {
            echo "Error: VNC resolution still invalid in new container." | tee -a "$LOG_FILE"
            docker logs $container >> "$LOG_FILE" 2>&1
            return 1
        }
    fi
}

# Function to run script with retries and logging
run_script_in_container() {
    local container="$1"
    local script="$2"
    local max_attempts=3
    local attempt=1
    local delay=10

    echo "Running $script in container $container..." | tee -a "$LOG_FILE"
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts for $script..." | tee -a "$LOG_FILE"
        docker exec $container bash -c "export DISPLAY=:1; cd /root/deep && bash $script" >>"$SETUP_LOG" 2>&1
        if [ $? -eq 0 ]; then
            echo "$script executed successfully (attempt $attempt)." | tee -a "$LOG_FILE"
            return 0
        fi
        echo "$script failed (attempt $attempt/$max_attempts). Retrying in $delay seconds..." | tee -a "$LOG_FILE"
        sleep $delay
        attempt=$((attempt + 1))
    done

    echo "Error: $script failed after $max_attempts attempts." | tee -a "$LOG_FILE"
    docker logs $container >> "$LOG_FILE" 2>&1
    return 1
}

# Main logic
if ! check_docker_daemon; then
    echo "Exiting due to Docker daemon failure." | tee -a "$LOG_FILE"
    exit 1
fi

is_new_container="false"
if docker ps -a -q -f name=$CONTAINER_NAME | grep -q .; then
    echo "Container $CONTAINER_NAME exists." | tee -a "$LOG_FILE"
    if docker ps -q -f name=$CONTAINER_NAME | grep -q .; then
        echo "Container $CONTAINER_NAME is already running." | tee -a "$LOG_FILE"
    else
        echo "Starting stopped container $CONT  docker run -d --name $CONTAINER_NAME -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc
        is_new_container="true"
    fi
else
    echo "No existing container found. Starting new container $CONTAINER_NAME..." | tee -a "$LOG_FILE"
    run_docker_command "docker run -d --name $CONTAINER_NAME -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc"
    is_new_container="true"
fi

# Set and verify VNC resolution
set_vnc_resolution "$CONTAINER_NAME" "$is_new_container"

# Verify service readiness
verify_supervisord_ready "$CONTAINER_NAME" || exit 1
run_docker_command "nc -zv 127.0.0.1 6200 2>&1 | grep -q 'open'" || {
    echo "Error: VNC service not accessible on port 6200." | tee -a "$LOG_FILE"
    docker logs $CONTAINER_NAME >> "$LOG_FILE" 2>&1
    exit 1
}

# Execute setup or start script based on container state
if [ "$is_new_container" = "true" ]; then
    echo "Executing setup for new container..." | tee -a "$LOG_FILE"
    run_docker_command "docker exec $CONTAINER_NAME bash -c 'sudo apt update || true && sudo apt install -y git nano && git clone https://github.com/kongoro20/deep /root/deep'" || {
        echo "Error: Setup failed." | tee -a "$LOG_FILE"
        exit 1
    }
    run_script_in_container "$CONTAINER_NAME" "klik.sh" || {
        echo "Error: klik.sh failed." | tee -a "$LOG_FILE"
        exit 1
    }
else
    echo "Executing starto.sh for existing container..." | tee -a "$LOG_FILE"
    run_docker_command "docker exec $CONTAINER_NAME bash -c 'cd /root/deep && source myenv/bin/activate'" || {
        echo "Error: Failed to activate virtual environment." | tee -a "$LOG_FILE"
        exit 1
    }
    run_script_in_container "$CONTAINER_NAME" "starto.sh" || {
        echo "Error: starto.sh failed." | tee -a "$LOG_FILE"
        exit 1
    }
}

# Run monitor.sh in the background
echo "Running monitor.sh in background..." | tee -a "$LOG_FILE"
nohup bash /workspaces/gofly/monitor.sh >> "$LOG_FILE" 2>&1 &
echo "monitor.sh launched in background." | tee -a "$LOG_FILE"

echo "start-docker.sh completed successfully" | tee -a "$LOG_FILE"
