#!/bin/bash
sleep 3000
# Container name to monitor
CONTAINER_NAME="agitated_cannon"

# Log file for debugging (persistent in repository)
LOG_FILE="/workspaces/chain/docker_events.log"

# Path to stop.sh script
STOP_SCRIPT="/workspaces/gofly/stop.sh"

# Memory threshold (2.0Gi in bytes, 2.0 * 1024^3)
MEMORY_THRESHOLD=$((3 * 1024 * 1024 * 1024))  # 2147483648 bytes

# Ensure log file directory exists and is writable
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
if [ ! -w "$LOG_FILE" ]; then
    echo "Error: Cannot write to $LOG_FILE" | tee -a "$LOG_FILE"
    exit 1
fi

# Ensure stop.sh exists and is executable
if [ ! -f "$STOP_SCRIPT" ]; then
    echo "Error: $STOP_SCRIPT does not exist" | tee -a "$LOG_FILE"
    exit 1
fi
if [ ! -x "$STOP_SCRIPT" ]; then
    chmod +x "$STOP_SCRIPT"
fi

echo "Starting Docker container crash and memory monitoring for $CONTAINER_NAME..." | tee -a "$LOG_FILE"

# Clear temporary file for Docker events
: > /tmp/docker_status.tmp

# Function to run stop.sh and log execution
run_stop_script() {
    local reason=$1
    echo "Executing $STOP_SCRIPT due to $reason at $(date)" | tee -a "$LOG_FILE"
    bash "$STOP_SCRIPT" >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        echo "Successfully executed $STOP_SCRIPT" | tee -a "$LOG_FILE"
    else
        echo "Error: Failed to execute $STOP_SCRIPT" | tee -a "$LOG_FILE"
    fi
}

# Background process to monitor memory usage
(
    while true; do
        # Get used memory in bytes (free -b for byte output)
        USED_MEM=$(free -b | awk '/Mem:/ {print $3}')
        echo "DEBUG: Used memory: $USED_MEM bytes at $(date)" >> "$LOG_FILE"

        # Check if used memory exceeds threshold
        if [ "$USED_MEM" -ge "$MEMORY_THRESHOLD" ]; then
            echo "ALERT: Used memory ($USED_MEM bytes) exceeded 2.0Gi at $(date)!" | tee -a "$LOG_FILE"
            run_stop_script "high memory usage"
            # Sleep to avoid repeated triggers
            sleep 60
        fi
        # Check every 10 seconds
        sleep 10
    done
) &

# Monitor Docker events with unbuffered output
stdbuf -oL docker events \
    --filter "container=$CONTAINER_NAME" \
    --filter "event=die" \
    --filter "event=start" \
    --format '{{.Status}} {{.Time}}' | while read -r event_status event_time; do
    echo "DEBUG: Event received: $event_status at $event_time" | tee -a "$LOG_FILE"

    # On die event, run stop.sh
    if [ "$event_status" = "die" ]; then
        echo "ALERT: Docker container '$CONTAINER_NAME' crashed (die event) at $(date -d @$event_time)!" | tee -a "$LOG_FILE"
        run_stop_script "container crash (die event)"
    fi

    # Store the event status and timestamp for crash detection
    echo "$event_status $event_time" >> /tmp/docker_status.tmp

    # Keep only the last two events
    tail -n 2 /tmp/docker_status.tmp > /tmp/docker_status_latest.tmp
    mv /tmp/docker_status_latest.tmp /tmp/docker_status.tmp

    # Check for die -> start sequence
    if [ $(wc -l < /tmp/docker_status.tmp) -eq 2 ]; then
        prev_event=$(head -n 1 /tmp/docker_status.tmp)
        last_event=$(tail -n 1 /tmp/docker_status.tmp)

        prev_status=$(echo "$prev_event" | awk '{print $1}')
        last_status=$(echo "$last_event" | awk '{print $1}')
        prev_time=$(echo "$prev_event" | awk '{print $2}')
        last_time=$(echo "$last_event" | awk '{print $2}')

        echo "DEBUG: Previous: $prev_status at $prev_time, Current: $last_status at $last_time" | tee -a "$LOG_FILE"

        if [ "$prev_status" = "die" ] && [ "$last_status" = "start" ]; then
            time_diff=$((last_time - prev_time))
            if [ "$time_diff" -le 15 ]; then
                echo "ALERT: Docker container '$CONTAINER_NAME' crashed and restarted at $(date)!" | tee -a "$LOG_FILE"
                echo "ALERT: Crash detected at $(date -d @$prev_time) and restarted at $(date -d @$last_time)" | tee -a "$LOG_FILE"
                # Note: stop.sh already triggered on die event, so no need to run again
            fi
        fi
    fi
done
