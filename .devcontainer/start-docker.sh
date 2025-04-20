#!/bin/bash

# Script to start Docker container on Codespace startup

# Check if the container exists (running or stopped)
if docker ps -a -q -f name=agitated_cannon | grep -q .; then
    # Check if the container is running
    if docker ps -q -f name=agitated_cannon | grep -q .; then
        echo "Docker container agitated_cannon is already running."
        exit 0
    else
        # Container exists but is stopped; start it
        echo "Starting stopped Docker container agitated_cannon..."
        docker start agitated_cannon
        if [ $? -eq 0 ]; then
            echo "Docker container agitated_cannon started successfully."
            exit 0
        else
            echo "Error: Failed to start Docker container agitated_cannon."
            exit 1
        fi
    fi
fi

# Container doesn't exist; create and run it
echo "Starting new Docker container agitated_cannon..."
docker run -d --name agitated_cannon -p 6200:80 -v /workspaces/gofly/docker-data:/home/ubuntu dorowu/ubuntu-desktop-lxde-vnc

if [ $? -eq 0 ]; then
    echo "Docker container agitated_cannon started successfully."
else
    echo "Error: Failed to start Docker container agitated_cannon."
    exit 1
fi
