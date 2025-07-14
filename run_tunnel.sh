#!/bin/bash

# Ensure SSH is running
if ! pgrep sshd > /dev/null; then
    echo "Starting SSH service..."
    service ssh start
    sleep 2
fi

# Set up logging
LOG=/kaggle/working/cloudflared.log
ERROR_LOG=/kaggle/working/cloudflared_error.log

# Kill any existing cloudflared processes
pkill -f cloudflared

# Start cloudflared tunnel
echo "Starting Cloudflared tunnel..."
nohup cloudflared tunnel --url tcp://localhost:22 --logfile "$LOG" > "$ERROR_LOG" 2>&1 &

# Wait for tunnel to establish
echo "Waiting for tunnel to establish..."
sleep 15

# Check if cloudflared is running
if ! pgrep -f cloudflared > /dev/null; then
    echo "ERROR: Cloudflared failed to start"
    echo "Error log:"
    cat "$ERROR_LOG"
    exit 1
fi

# Extract SSH endpoint
echo "==========  SSH endpoint for VS Code / PuTTY  =========="
if [ -f "$LOG" ]; then
    # Try multiple patterns to extract the SSH endpoint
    ENDPOINT=$(grep -oP 'https://[^/]+\.trycloudflare\.com' "$LOG" | head -n1)
    if [ -z "$ENDPOINT" ]; then
        ENDPOINT=$(grep -oP 'ssh://[^/]+\.trycloudflare\.com:\d+' "$LOG" | head -n1)
    fi
    
    if [ -n "$ENDPOINT" ]; then
        # Convert https to ssh format if needed
        if [[ $ENDPOINT == https://* ]]; then
            DOMAIN=$(echo $ENDPOINT | sed 's/https:\/\///')
            echo "ssh root@$DOMAIN -p 22"
        else
            echo "$ENDPOINT"
        fi
    else
        echo "Could not extract endpoint from log. Raw log content:"
        cat "$LOG"
    fi
else
    echo "Log file not found. Error log:"
    cat "$ERROR_LOG"
fi
echo "========================================================="

# Keep the tunnel alive
echo "Tunnel is running. Press Ctrl+C to stop."
tail -f "$LOG" &
wait