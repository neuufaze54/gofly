#!/bin/bash

# Script to start Docker container on Codespace startup

# Check if the container is already running
if docker ps -q -f name=agitated_cannon | grep -q .; then
    echo "Docker container agitated_cannon is already running."
    exit 0
fi

# Start the container with the same parameters
echo "Starting Docker container agitated_cannon..."
docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu dorowu/ubuntu-desktop-lxde-vnc

if [ $? -eq 0 ]; then
    echo "Docker container agitated_cannon started successfully."
else
    echo "Error: Failed to start Docker container agitated_cannon."
    exit 1
fi
