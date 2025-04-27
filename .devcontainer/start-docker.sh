#!/bin/bash

# Script to start Docker container on Codespace startup
# Updated on 2025-05-01 to run monitor.sh before klik.sh/starto.sh in background
# Updated on 2025-05-02 to sleep 30 seconds after launching commands to allow stabilization

LOG_FILE="/workspaces/gofly/start-docker.log"
SETUP_LOG="/workspaces/gofly/setup.log"
MONITOR_LOG="/workspaces/gofly/monitor.log"
CONTAINER_NAME="agitated_cannon"
HEALTH_LOG="/workspaces/gofly/health.log"
echo "start-docker.sh started at $(date)" > "$LOG_FILE"

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

verify_supervisord_ready() {
    local container="$1"
    local max_attempts=10
    local attempt=1
    local delay=5

    echo "Verifying supervisord is ready in container $container..." | tee -a "$LOG_FILE"
    while [ $attempt -le $max_attempts ]; do
        if docker exec $container bash -c "supervisorctl status | grep -q RUNNING" 2>/dev/null; then
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

set_vnc_resolution() {
    local container="$1"
    local is_new_container="$2"
    echo "Setting VNC resolution to 1366x641 for container $container..." | tee -a "$LOG_FILE"

    run_docker_command "docker exec $container bash -c 'sed -i \"s/-screen 0 [0-9x]*24/-screen 0 1366x641x24/\" /etc/supervisor/conf.d/supervisord.conf || echo \"command=Xvfb :1 -screen 0 1366x641x24\" >> /etc/supervisor/conf.d/supervisord.conf'"
    run_docker_command "docker exec $container bash -c 'sed -i \"s/user=%USER%/user=root/\" /etc/supervisor/conf.d/supervisord.conf'"
    run_docker_command "docker exec $container bash -c 'sed -i \"s/HOME=\\\"%HOME%\\\"/HOME=\\\"\/root\\\"/\" /etc/supervisor/conf.d/supervisord.conf'"
    run_docker_command "docker exec $container bash -c 'sed -i \"s/command=x11vnc .*/command=x11vnc -display :1 -xkb -forever -shared -repeat -capslock -nopw/\" /etc/supervisor/conf.d/supervisord.conf'"

    echo "Configuring X11 authentication..." | tee -a "$LOG_FILE"
    run_docker_command "docker exec $container bash -c 'rm -f /root/.Xauthority && touch /root/.Xauthority && xauth add :1 . \$(mcookie)'" || echo "Warning: Failed to configure X11 authentication." | tee -a "$LOG_FILE"

    echo "Supervisord configuration after update:" >> "$LOG_FILE"
    docker exec $container bash -c "cat /etc/supervisor/conf.d/supervisord.conf" >> "$LOG_FILE" 2>&1

    if [ "$is_new_container" = "false" ]; then
        verify_supervisord_ready "$container"
        echo "Restarting Xvfb and x11vnc services..." | tee -a "$LOG_FILE"
        run_docker_command "docker exec $container bash -c 'supervisorctl restart x:xvfb'" || echo "Warning: Failed to restart Xvfb." | tee -a "$LOG_FILE"
        sleep 2
        run_docker_command "docker exec $container bash -c 'supervisorctl restart x:x11vnc'" || echo "Warning: Failed to restart x11vnc." | tee -a "$LOG_FILE"
    fi

    echo "Waiting 10 seconds for services to stabilize..." | tee -a "$LOG_FILE"
    sleep 10

    echo "Supervisord status after restarts:" >> "$LOG_FILE"
    docker exec $container bash -c "supervisorctl status" >> "$LOG_FILE" 2>&1

    if verify_vnc_resolution "$container"; then
        echo "VNC resolution set and verified successfully." | tee -a "$LOG_FILE"
    else
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

    echo "Container startup logs:" >> "$LOG_FILE"
    docker logs $container >> "$LOG_FILE" 2>&1
}

start_container() {
    local is_new_container="$1"
    if [ "$is_new_container" = "true" ]; then
        echo "Starting new Docker container $CONTAINER_NAME..." | tee -a "$LOG_FILE"
        run_docker_command "docker run -d --name $CONTAINER_NAME -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc"
    else
        echo "Starting stopped Docker container $CONTAINER_NAME..." | tee -a "$LOG_FILE"
        run_docker_command "docker start $CONTAINER_NAME" || {
            echo "Removing failed container $CONTAINER_NAME to recreate it..." | tee -a "$LOG_FILE"
            run_docker_command "docker rm $CONTAINER_NAME"
            run_docker_command "docker run -d --name $CONTAINER_NAME -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc"
            is_new_container="true"
        }
    fi
    echo "Docker container $CONTAINER_NAME started successfully." | tee -a "$LOG_FILE"
    sleep 10
    set_vnc_resolution "$CONTAINER_NAME" "$is_new_container"
    verify_supervisord_ready "$CONTAINER_NAME" || exit 1
    run_docker_command "nc -zv 127.0.0.1 6200 2>&1 | grep -q 'open'" || {
        echo "Error: VNC service not accessible on port 6200." | tee -a "$LOG_FILE"
        docker logs $CONTAINER_NAME >> "$LOG_FILE" 2>&1
        exit 1
    }
    return 0
}

start_monitor() {
    local max_attempts=3
    local attempt=1
    local delay=5

    echo "Attempting to start monitor.sh on host..." | tee -a "$LOG_FILE"
    if [ ! -f /workspaces/gofly/monitor.sh ]; then
        echo "Error: monitor.sh not found at /workspaces/gofly/monitor.sh." | tee -a "$LOG_FILE"
        return 1
    fi
    chmod +x /workspaces/gofly/monitor.sh || {
        echo "Error: Failed to make monitor.sh executable." | tee -a "$LOG_FILE"
        return 1
    }
    # Validate monitor.sh has shebang
    if ! head -n 1 /workspaces/gofly/monitor.sh | grep -q "^#!/bin/bash"; then
        echo "Warning: monitor.sh missing shebang (#!/bin/bash). Adding it..." | tee -a "$LOG_FILE"
        echo -e "#!/bin/bash\n$(cat /workspaces/gofly/monitor.sh)" > /workspaces/gofly/monitor.sh.tmp
        mv /workspaces/gofly/monitor.sh.tmp /workspaces/gofly/monitor.sh
        chmod +x /workspaces/gofly/monitor.sh
    fi
    # Check monitor.sh syntax
    if ! bash -n /workspaces/gofly/monitor.sh >/dev/null 2>&1; then
        echo "Error: monitor.sh contains syntax errors. Check script content." | tee -a "$LOG_FILE"
        bash -n /workspaces/gofly/monitor.sh >> "$LOG_FILE" 2>&1
        return 1
    fi

    while [ $attempt -le $max_attempts ]; do
        echo "Starting monitor.sh (attempt $attempt/$max_attempts)..." | tee -a "$LOG_FILE"
        > "$MONITOR_LOG" # Clear monitor.log
        nohup bash /workspaces/gofly/monitor.sh >> "$MONITOR_LOG" 2>&1 &
        local monitor_pid=$!
        sleep 2
        if ps -p $monitor_pid >/dev/null 2>&1; then
            echo "monitor.sh started successfully with PID $monitor_pid." | tee -a "$LOG_FILE"
            return 0
        else
            echo "monitor.sh failed to start (attempt $attempt/$max_attempts). Check $MONITOR_LOG for errors." | tee -a "$LOG_FILE"
            cat "$MONITOR_LOG" >> "$LOG_FILE" 2>&1
            if [ $attempt -eq $max_attempts ]; then
                echo "Error: monitor.sh failed after $max_attempts attempts." | tee -a "$LOG_FILE"
                return 1
            fi
            echo "Retrying in $delay seconds..." | tee -a "$LOG_FILE"
            sleep $delay
            attempt=$((attempt + 1))
        fi
    done
}

monitor_processes() {
    local is_new_container="$1"
    echo "Starting process monitoring for container $CONTAINER_NAME..." | tee -a "$LOG_FILE"
    while true; do
        if [ "$is_new_container" = "true" ]; then
            # Check for klik.sh or its child processes (e.g., detector scripts)
            if ! docker exec $CONTAINER_NAME bash -c "ps aux | grep -E '[k]lik.sh|[d]etector.*\.py' | grep -v grep" >/dev/null 2>&1; then
                echo "Critical process (klik.sh or detectors) not running at $(date). Restarting container..." | tee -a "$HEALTH_LOG"
                return 1
            fi
        else
            # Check for starto.sh or its child processes
            if ! docker exec $CONTAINER_NAME bash -c "ps aux | grep -E '[s]tarto.sh|[d]etector.*\.py' | grep -v grep" >/dev/null 2>&1; then
                echo "Critical process (starto.sh or detectors) not running at $(date). Restarting container..." | tee -a "$HEALTH_LOG"
                return 1
            fi
        fi

        # Check for monitor.sh on host
        if ! pgrep -f "bash /workspaces/gofly/monitor.sh" >/dev/null 2>&1; then
            echo "monitor.sh not running at $(date). Restarting container..." | tee -a "$HEALTH_LOG"
            return 1
        fi

        echo "All critical processes running at $(date)." >> "$HEALTH_LOG"
        # Debug process status
        echo "Process status at $(date):" >> "$HEALTH_LOG"
        docker exec $CONTAINER_NAME bash -c "ps aux | grep -E '[k]lik.sh|[s]tarto.sh|[d]etector.*\.py' || true" >> "$HEALTH_LOG" 2>&1
        ps aux | grep "[b]ash /workspaces/gofly/monitor.sh" >> "$HEALTH_LOG" 2>&1 || echo "No monitor.sh process found." >> "$HEALTH_LOG"
        sleep 200
    done
}

# Main logic
if ! check_docker_daemon; then
    echo "Exiting due to Docker daemon failure." | tee -a "$LOG_FILE"
    exit 1
fi

while true; do
    is_new_container="false"
    if docker ps -a -q -f name=$CONTAINER_NAME | grep -q .; then
        echo "Container $CONTAINER_NAME exists." | tee -a "$LOG_FILE"
        if docker ps -q -f name=$CONTAINER_NAME | grep -q .; then
            echo "Container $CONTAINER_NAME is already running." | tee -a "$LOG_FILE"
            set_vnc_resolution "$CONTAINER_NAME" "false"
        else
            start_container "false"
            is_new_container="false"
        fi
    else
        is_new_container="true"
        start_container "true"
    fi

    # Execute commands based on container state
    echo "Executing commands for container (is_new_container=$is_new_container)..." | tee -a "$LOG_FILE"
    if [ "$is_new_container" = "true" ]; then
        # Start monitor.sh in background
        echo "Launching monitor.sh before preparatory commands and klik.sh..." | tee -a "$LOG_FILE"
        if ! start_monitor; then
            echo "Error: Failed to start monitor.sh. Restarting container..." | tee -a "$LOG_FILE"
            run_docker_command "docker stop $CONTAINER_NAME" || echo "Warning: Failed to stop container." | tee -a "$LOG_FILE"
            run_docker_command "docker rm $CONTAINER_NAME" || echo "Warning: Failed to remove container." | tee -a "$LOG_FILE"
            continue
        fi
        # Run preparatory commands and klik.sh in background
        echo "Launching preparatory commands and klik.sh in background..." | tee -a "$LOG_FILE"
        docker exec $CONTAINER_NAME bash -c "sudo apt update || true && sudo apt install -y git nano xauth && git clone https://github.com/kongoro20/deep /root/deep && cd /root/deep && export DISPLAY=:1 && bash klik.sh >> /workspaces/gofly/setup.log 2>&1 &" || {
            echo "Error: Failed to launch preparatory commands or klik.sh." | tee -a "$LOG_FILE"
            run_docker_command "docker stop $CONTAINER_NAME" || echo "Warning: Failed to stop container." | tee -a "$LOG_FILE"
            run_docker_command "docker rm $CONTAINER_NAME" || echo "Warning: Failed to remove container." | tee -a "$LOG_FILE"
            continue
        }
    else
        # Start monitor.sh in background
        echo "Launching monitor.sh before starto.sh..." | tee -a "$LOG_FILE"
        if ! start_monitor; then
            echo "Error: Failed to start monitor.sh. Restarting container..." | tee -a "$LOG_FILE"
            run_docker_command "docker stop $CONTAINER_NAME" || echo "Warning: Failed to stop container." | tee -a "$LOG_FILE"
            run_docker_command "docker rm $CONTAINER_NAME" || echo "Warning: Failed to remove container." | tee -a "$LOG_FILE"
            continue
        fi
        # Run starto.sh in background
        echo "Launching starto.sh in background..." | tee -a "$LOG_FILE"
        docker exec $CONTAINER_NAME bash -c "cd /root/deep && source myenv/bin/activate && export DISPLAY=:1 && bash starto.sh >> /workspaces/gofly/setup.log 2>&1 &" || {
            echo "Error: Failed to launch starto.sh." | tee -a "$LOG_FILE"
            run_docker_command "docker stop $CONTAINER_NAME" || echo "Warning: Failed to stop container." | tee -a "$LOG_FILE"
            run_docker_command "docker rm $CONTAINER_NAME" || echo "Warning: Failed to remove container." | tee -a "$LOG_FILE"
            continue
        }
    fi

    # Wait for commands to stabilize
    echo "Sleeping for 30 seconds to allow commands to stabilize..." | tee -a "$LOG_FILE"
    sleep 30

    # Verify monitor.sh is running
    if ! pgrep -f "bash /workspaces/gofly/monitor.sh" >/dev/null 2>&1; then
        echo "Error: monitor.sh not running after startup. Check $MONITOR_LOG for errors." | tee -a "$LOG_FILE"
        cat "$MONITOR_LOG" >> "$LOG_FILE" 2>&1
        run_docker_command "docker stop $CONTAINER_NAME" || echo "Warning: Failed to stop container." | tee -a "$LOG_FILE"
        run_docker_command "docker rm $CONTAINER_NAME" || echo "Warning: Failed to remove container." | tee -a "$LOG_FILE"
        continue
    fi

    # Monitor processes and restart container if any fail
    echo "Entering process monitoring loop..." | tee -a "$LOG_FILE"
    if ! monitor_processes "$is_new_container"; then
        echo "Stopping and removing container $CONTAINER_NAME due to process failure..." | tee -a "$LOG_FILE"
        run_docker_command "docker stop $CONTAINER_NAME" || echo "Warning: Failed to stop container." | tee -a "$LOG_FILE"
        run_docker_command "docker rm $CONTAINER_NAME" || echo "Warning: Failed to remove container." | tee -a "$LOG_FILE"
        continue
    fi
done

echo "start-docker.sh completed successfully" | tee -a "$LOG_FILE"
