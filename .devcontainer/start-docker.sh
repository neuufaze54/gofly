#!/bin/bash
# Script to start Docker container on Codespace startup
set -e
echo "Checking Docker service..."
if ! service docker status | grep -q "running"; then
    echo "Starting Docker service..."
    sudo service docker start
    sleep 5
fi
# Remove any stopped container
if docker ps -a -q -f name=agitated_cannon | grep -q .; then
    echo "Removing existing agitated_cannon container..."
    docker rm -f agitated_cannon
fi
# Start new container
echo "Starting new Docker container agitated_cannon..."
docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu dorowu/ubuntu-desktop-lxde-vnc
if [ $? -eq 0 ]; then
    echo "Docker container agitated_cannon started successfully."
    # Wait for container to be healthy
    echo "Waiting for container to be healthy..."
    for i in {1..30}; do
        if docker inspect agitated_cannon | grep -q '"Status": "healthy"'; then
            echo "Container is healthy."
            break
        fi
        echo "Container not healthy yet, retrying in 5 seconds ($i/30)..."
        sleep 5
    done
    if [ $i -eq 30 ]; then
        echo "Error: Container did not become healthy."
        docker logs agitated_cannon
        exit 1
    fi
else
    echo "Error: Failed to start Docker container agitated_cannon."
    docker logs agitated_cannon
    exit 1
fi
echo "Verifying port 6200..."
if nc -z localhost 6200; then
    echo "Port 6200 is listening."
else
    echo "Error: Port 6200 is not listening."
    docker logs agitated_cannon
    exit 1
fi
