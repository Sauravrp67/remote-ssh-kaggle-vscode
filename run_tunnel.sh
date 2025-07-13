
LOG=/kaggle/working/cloudflared.log
nohup cloudflared tunnel --url tcp://localhost:22 --logfile "$LOG" >/dev/null 2>&1 &

# Give it a couple of seconds to connect
sleep 10

echo "==========  SSH endpoint for VS Code / PuTTY  =========="
grep -oP 'ssh://\K[^ ]+' "$LOG" | head -n1
echo "========================================================="