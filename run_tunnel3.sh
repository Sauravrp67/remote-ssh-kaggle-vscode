#!/bin/bash

# Bulletproof tunnel script that completely detaches from TTY
LOG=/kaggle/working/cloudflared.log
PID_FILE=/kaggle/working/cloudflared.pid

# Kill any existing processes
pkill -f cloudflared
sleep 2

# Clear logs
> "$LOG"

# Create a wrapper script that will run cloudflared completely detached
cat > /tmp/cloudflared_wrapper.sh << 'EOF'
#!/bin/bash
exec cloudflared tunnel \
    --url tcp://localhost:22 \
    --protocol http2 \
    --loglevel info \
    --logfile /kaggle/working/cloudflared.log \
    --no-autoupdate \
    --no-quic
EOF

chmod +x /tmp/cloudflared_wrapper.sh

# Start cloudflared in a completely detached way
echo "Starting Cloudflared tunnel (detached)..."
setsid nohup /tmp/cloudflared_wrapper.sh </dev/null >/dev/null 2>&1 &

# Wait a moment for it to start
sleep 3

# Find the actual cloudflared PID
CLOUDFLARED_PID=$(pgrep -f "cloudflared tunnel")
echo "Cloudflared PID: $CLOUDFLARED_PID"

if [ -z "$CLOUDFLARED_PID" ]; then
    echo "ERROR: Failed to start cloudflared"
    exit 1
fi

# Save PID for later management
echo "$CLOUDFLARED_PID" > "$PID_FILE"

echo "Cloudflared started with PID: $CLOUDFLARED_PID"

# Wait for tunnel to establish
echo "Waiting for tunnel to establish..."
for i in {1..30}; do
    if ! kill -0 "$CLOUDFLARED_PID" 2>/dev/null; then
        echo "ERROR: cloudflared process died after $i seconds"
        if [ -f "$LOG" ]; then
            echo "Log content:"
            cat "$LOG"
        fi
        exit 1
    fi
    
    # Check for tunnel URL
    if [ -f "$LOG" ] && grep -q "https://.*\.trycloudflare\.com" "$LOG" 2>/dev/null; then
        echo "Tunnel established after $i seconds"
        break
    fi
    
    echo "Waiting... ($i/30)"
    sleep 1
done

# Extract and display tunnel info
if [ -f "$LOG" ]; then
    echo "==========  SSH endpoint for VS Code / PuTTY  =========="
    ENDPOINT=$(grep -oP 'https://\K[^/]+\.trycloudflare\.com' "$LOG" | head -n1)
    if [ -n "$ENDPOINT" ]; then
        echo "ssh root@$ENDPOINT -p 22"
    else
        echo "Could not extract endpoint. Log content:"
        cat "$LOG"
    fi
    echo "========================================================="
fi

echo "Tunnel is running in background (PID: $CLOUDFLARED_PID)"
echo "To stop: kill $CLOUDFLARED_PID"
echo "To check status: ps aux | grep cloudflared"