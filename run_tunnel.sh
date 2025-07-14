#!/bin/bash

# Ensure SSH is running
if ! pgrep sshd > /dev/null; then
    echo "Starting SSH service..."
    service ssh start
    sleep 2
fi

# Verify SSH is actually listening on port 22
if ! netstat -tlnp | grep :22 > /dev/null; then
    echo "ERROR: SSH is not listening on port 22"
    service ssh status
    exit 1
fi

# Set up logging
LOG=/kaggle/working/cloudflared.log
ERROR_LOG=/kaggle/working/cloudflared_error.log

# Kill any existing cloudflared processes
pkill -f cloudflared
sleep 2

# Clear previous logs
> "$LOG"
> "$ERROR_LOG"

# Test cloudflared first
echo "Testing cloudflared installation..."
if ! cloudflared --version; then
    echo "ERROR: cloudflared not properly installed"
    exit 1
fi

# Start cloudflared tunnel with more conservative approach
echo "Starting Cloudflared tunnel..."
cloudflared tunnel --url tcp://localhost:22 --logfile "$LOG" > "$ERROR_LOG" 2>&1 &
CLOUDFLARED_PID=$!

# Wait incrementally and check if process is still running
echo "Waiting for tunnel to establish..."
for i in {1..30}; do
    if ! kill -0 $CLOUDFLARED_PID 2>/dev/null; then
        echo "ERROR: cloudflared process died after $i seconds"
        echo "Error log content:"
        cat "$ERROR_LOG"
        echo "Regular log content:"
        cat "$LOG"
        exit 1
    fi
    
    # Check if we have a tunnel URL yet
    if grep -q "https://.*\.trycloudflare\.com" "$LOG" 2>/dev/null; then
        echo "Tunnel established after $i seconds"
        break
    fi
    
    echo "Waiting... ($i/30)"
    sleep 1
done

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