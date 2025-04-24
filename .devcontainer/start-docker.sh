#!/bin/bash
set -e
LOG_FILE="/workspaces/gofly/start-docker.log"
echo "Starting start-docker.sh at $(date)" | tee -a $LOG_FILE
echo "Running as user: $(whoami)" | tee -a $LOG_FILE
echo "Docker environment:" | tee -a $LOG_FILE
env | grep DOCKER >> $LOG_FILE 2>&1
echo "Checking Docker daemon..." | tee -a $LOG_FILE
if ! docker info --format '{{.ServerVersion}}' >> $LOG_FILE 2>&1; then
    echo "Error: Docker daemon is not running" | tee -a $LOG_FILE
    docker info >> $LOG_FILE 2>&1
    exit 1
fi
echo "Docker daemon is running" | tee -a $LOG_FILE
if docker ps -a -q -f name=agitated_cannon | grep -q .; then
    echo "Removing existing agitated_cannon container..." | tee -a $LOG_FILE
    docker rm -f agitated_cannon >> $LOG_FILE 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to remove existing container" | tee -a $LOG_FILE
        exit 1
    fi
fi
echo "Starting new Docker container agitated_cannon..." | tee -a $LOG_FILE
docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu dorowu/ubuntu-desktop-lxde-vnc >> $LOG_FILE 2>&1
if [ $? -eq 0 ]; then
    echo "Docker container agitated_cannon started successfully" | tee -a $LOG_FILE
    echo "Waiting for container to be healthy..." | tee -a $LOG_FILE
    for i in {1..30}; do
        if docker inspect agitated_cannon | grep -q '"Status": "healthy"'; then
            echo "Container is healthy" | tee -a $LOG_FILE
            break
        fi
        echo "Container not healthy yet, retrying in 5 seconds ($i/30)..." | tee -a $LOG_FILE
        sleep 5
    done
    if [ $i -eq 30 ]; then
        echo "Error: Container did not become healthy" | tee -a $LOG_FILE
        docker logs agitated_cannon >> $LOG_FILE 2>&1
        exit 1
    fi
else
    echo "Error: Failed to start Docker container agitated_cannon" | tee -a $LOG_FILE
    docker logs agitated_cannon >> $LOG_FILE 2>&1
    exit 1
fi
echo "Verifying port 6200..." | tee -a $LOG_FILE
if curl -s -I http://localhost:6200 | grep -q "HTTP/1.1 200 OK"; then
    echo "Port 6200 is listening" | tee -a $LOG_FILE
else
    echo "Error: Port 6200 is not listening" | tee -a $LOG_FILE
    docker logs agitated_cannon >> $LOG_FILE 2>&1
    exit 1
fi
echo "start-docker.sh completed successfully at $(date)" | tee -a $LOG_FILE
