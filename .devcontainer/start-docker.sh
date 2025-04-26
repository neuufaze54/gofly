#!/bin/bash

# Script to start Docker container on Codespace startup
# Updated on 2025-04-25 to add delay before initial resolution check and stabilize x11vnc
# Updated on 2025-04-25 to directly execute klik.sh from known path
# Updated on 2025-04-25 to improve supervisord service restarts and resolution verification
# Updated on 2025-04-25 to run setup commands for new containers and different commands for existing containers
# Updated on 2025-04-26 to replace memory usage monitoring with execution of monitor.sh
# Updated on 2025-04-26 to ensure background commands execute reliably during Codespace startup
LOG_FILE="/workspaces/gofly/start-docker.log"
SETUP_LOG="/workspaces/gofly/setup.log"
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
    local max_attempts=5
    local attempt=1
    local delay=5

    echo "Verifying supervisord is ready in container $container..." | tee -a "$LOG_FILE"
    while [ $attempt -le $max_attempts ]; do
        if docker exec $container bash -c "supervisorctl status" >/dev/null 2>&1; then
            echo "Supervisord is ready (attempt $attempt)." | tee -a "$LOG_FILE"
            return 0
        fi
        echo "Supervisord not ready (attempt $attempt/$max_attempts). Retrying in $delay seconds..." | tee -a "$LOG_FILE"
        sleep $delay
        attempt=$((attempt + 1))
    done

    echo "Warning: Supervisord not ready after $max_attempts attempts. Continuing..." | tee -a "$LOG_FILE"
    return 1
}

verify_network_ready() {
    local container="$1"
    local max_attempts=5
    local attempt=1
    local delay=5

    echo "Verifying network is ready in container $container..." | tee -a "$LOG_FILE"
    while [ $attempt -le $max_attempts ]; do
        if docker exec $container bash -c "ping -c 1 github.com" >/dev/null 2>&1; then
            echo "Network is ready (attempt $attempt)." | tee -a "$LOG_FILE"
            return 0
        fi
        echo "Network not ready (attempt $attempt/$max_attempts). Retrying in $delay seconds..." | tee -a "$LOG_FILE"
        sleep $delay
        attempt=$((attempt + 1))
    done

    echo "Warning: Network not ready after $max_attempts attempts. Continuing..." | tee -a "$LOG_FILE"
    return 1
}

verify_vnc_resolution() {
    local container="$1"
    local max_attempts=3
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

    echo "Warning: VNC resolution is $resolution, expected 1366x641 after $max_attempts attempts." | tee -a "$LOG_FILE"
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

    echo "Supervisord configuration after update:" >> "$LOG_FILE"
    docker exec $container bash -c "cat /etc/supervisor/conf.d/supervisord.conf" >> "$LOG_FILE" 2>&1

    if [ "$is_new_container" = "false" ]; then
        verify_supervisord_ready "$container"

        echo "Restarting Xvfb and x11vnc services..." | tee -a "$LOG_FILE"
        run_docker_command "docker exec $container bash -c 'supervisorctl restart x:xvfb'" || echo "Warning: Failed to restart Xvfb service after retries. Continuing..." | tee -a "$LOG_FILE"
        sleep 2
        run_docker_command "docker exec $container bash -c 'supervisorctl restart x:x11vnc'" || echo "Warning: Failed to restart x11vnc service after retries. Continuing..." | tee -a "$LOG_FILE"
    else
        echo "Skipping service restarts for new container, relying on supervisord startup." | tee -a "$LOG_FILE"
    fi

    echo "Waiting 10 seconds for services to stabilize..." | tee -a "$LOG_FILE"
    sleep 10

    echo "Supervisord status after restarts:" >> "$LOG_FILE"
    docker exec $container bash -c "supervisorctl status" >> "$LOG_FILE" 2>&1

    if verify_vnc_resolution "$container"; then
        echo "VNC resolution set and verified successfully." | tee -a "$LOG_FILE"
    else
        echo "Error: Failed to verify VNC resolution after retries. Attempting container restart..." | tee -a "$LOG_FILE"
        if run_docker_command "docker restart $container"; then
            echo "Container $container restarted successfully." | tee -a "$LOG_FILE"
            sleep 10
            if verify_vnc_resolution "$container"; then
                echo "VNC resolution verified after container restart." | tee -a "$LOG_FILE"
            else
                echo "Error: VNC resolution still invalid after container restart. Removing and recreating container..." | tee -a "$LOG_FILE"
                run_docker_command "docker rm -f $container" || {
                    echo "Error: Failed to remove container $container." | tee -a "$LOG_FILE"
                    docker logs $container >> "$LOG_FILE" 2>&1
                    return 1
                }
                echo "Creating new container $container..." | tee -a "$LOG_FILE"
                run_docker_command "docker run -d --name $container -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc" || {
                    echo "Error: Failed to create new container $container." | tee -a "$LOG_FILE"
                    docker logs $container >> "$LOG_FILE" 2>&1
                    return 1
                }
                echo "New container $container created successfully." | tee -a "$LOG_FILE"
                set_vnc_resolution "$container" "true"
                if ! verify_vnc_resolution "$container"; then
                    echo "Error: VNC resolution still invalid in new container." | tee -a "$LOG_FILE"
                    docker logs $container >> "$LOG_FILE" 2>&1
                    return 1
                fi
            fi
        else
            echo "Error: Failed to restart container $container. Removing and recreating container..." | tee -a "$LOG_FILE"
            run_docker_command "docker rm -f $container" || {
                echo "Error: Failed to remove container $container." | tee -a "$LOG_FILE"
                docker logs $container >> "$LOG_FILE" 2>&1
                return 1
            }
            echo "Creating new container $container..." | tee -a "$LOG_FILE"
            run_docker_command "docker run -d --name $container -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc" || {
                echo "Error: Failed to create new container $container." | tee -a "$LOG_FILE"
                docker logs $container >> "$LOG_FILE" 2>&1
                return 1
            }
            echo "New container $container created successfully." | tee -a "$LOG_FILE"
            set_vnc_resolution "$container" "true"
            if ! verify_vnc_resolution "$container"; then
                echo "Error: VNC resolution still invalid in new container." | tee -a "$LOG_FILE"
                docker logs $container >> "$LOG_FILE" 2>&1
                return 1
            fi
        fi
    fi

    echo "Container startup logs:" >> "$LOG_FILE"
    docker logs $container >> "$LOG_FILE" 2>&1
    echo "CPU usage inside container:" >> "$LOG_FILE"
    docker exec $container bash -c "top -bn1 | head -n 10" >> "$LOG_FILE" 2>&1
}

if ! check_docker_daemon; then
    echo "Exiting due to persistent Docker daemon failure." | tee -a "$LOG_FILE"
    exit 1
fi

is_new_container="false"
if docker ps -a -q -f name=agitated_cannon | grep -q .; then
    echo "Container agitated_cannon exists." | tee -a "$LOG_FILE"
    if docker ps -q -f name=agitated_cannon | grep -q .; then
        echo "Docker container agitated_cannon is already running." | tee -a "$LOG_FILE"
        echo "Waiting 10 seconds for services to stabilize..." | tee -a "$LOG_FILE"
        sleep 10
        verify_vnc_resolution "agitated_cannon" || set_vnc_resolution "agitated_cannon" "false"
    else
        echo "Starting stopped Docker container agitated_cannon..." | tee -a "$LOG_FILE"
        run_docker_command "docker start agitated_cannon" || {
            echo "Removing failed container agitated_cannon to recreate it..." | tee -a "$LOG_FILE"
            run_docker_command "docker rm agitated_cannon"
            run_docker_command "docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc"
            is_new_container="true"
            set_vnc_resolution "agitated_cannon" "true"
        }
        echo "Docker container agitated_cannon started successfully." | tee -a "$LOG_FILE"
        sleep 10
        verify_vnc_resolution "agitated_cannon" || set_vnc_resolution "agitated_cannon" "false"
    fi
else
    echo "No existing container found. Starting new Docker container agitated_cannon..." | tee -a "$LOG_FILE"
    run_docker_command "docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu -e VNC_RESOLUTION=1366x641 -e RESOLUTION=1366x641 dorowu/ubuntu-desktop-lxde-vnc"
    is_new_container="true"
    set_vnc_resolution "agitated_cannon" "true"
fi

sleep 5
if run_docker_command "nc -zv 127.0.0.1 6200 2>&1 | grep -q 'open'"; then
    echo "VNC service is accessible on port 6200." | tee -a "$LOG_FILE"

    # Ensure container services and network are fully initialized
    echo "Waiting for container services to fully initialize..." | tee -a "$LOG_FILE"
    verify_supervisord_ready "agitated_cannon"
    verify_network_ready "agitated_cannon"
    sleep 10

    if [ "$is_new_container" = "true" ]; then
        echo "Executing setup and klik.sh for new container in background..." | tee -a "$LOG_FILE"
        # Run setup command in background with nohup to prevent detachment
        nohup docker exec agitated_cannon bash -c 'sudo apt update || true && sudo apt install -y git nano && git clone https://github.com/kongoro20/deep /root/deep && cd /root/deep && DISPLAY=:1 source klik.sh' >>"$SETUP_LOG" 2>&1 &
        echo "Setup command launched in background. Output logged to $SETUP_LOG." | tee -a "$LOG_FILE"
    else
        echo "Executing starto.sh for existing container in background..." | tee -a "$LOG_FILE"
        nohup docker exec agitated_cannon bash -c 'export DISPLAY=:1; cd /root/deep && source myenv/bin/activate && bash starto.sh' >>"$SETUP_LOG" 2>&1 &
        echo "Starto.sh launched in background. Output logged to $SETUP_LOG." | tee -a "$LOG_FILE"
    fi

    echo "Running monitor.sh in background..." | tee -a "$LOG_FILE"
    nohup bash /workspaces/gofly/monitor.sh >> "$LOG_FILE" 2>&1 &
    echo "monitor.sh launched in background." | tee -a "$LOG_FILE"

    echo "start-docker.sh completed successfully" | tee -a "$LOG_FILE"
else
    echo "Error: VNC service is not accessible on port 6200." | tee -a "$LOG_FILE"
    docker logs agitated_cannon >> "$LOG_FILE" 2>&1
    exit 1
fi
