#!/bin/bash

# Create SSH directory
mkdir -p /kaggle/working/.ssh

# Download and setup public key
echo "Downloading public key from: $1"
wget "$1" -O /kaggle/working/.ssh/authorized_keys

# Set proper permissions
chmod 700 /kaggle/working/.ssh
chmod 600 /kaggle/working/.ssh/authorized_keys

# Install Cloudflared if not present
if ! command -v cloudflared >/dev/null 2>&1; then
    echo "Installing Cloudflared..."
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
         -O /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
fi

# Install SSH Server
echo "Installing SSH Server..."
apt-get update -qq
apt-get install -qq -y openssh-server

# Create necessary directories
mkdir -p /var/run/sshd
mkdir -p /root/.ssh

# Copy authorized keys to root (since we'll login as root)
cp /kaggle/working/.ssh/authorized_keys /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Clear existing SSH config and set new one
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Create clean SSH config
cat > /etc/ssh/sshd_config << EOF
# Basic SSH configuration for Kaggle
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_dsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication
PermitRootLogin yes
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile /root/.ssh/authorized_keys
IgnoreRhosts yes
HostbasedAuthentication no

# Other settings
TCPKeepAlive yes
X11Forwarding yes
X11DisplayOffset 10
PrintLastLog yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# Generate host keys if they don't exist
ssh-keygen -A

# Set up environment for root
echo "export LD_LIBRARY_PATH=/usr/lib64-nvidia:/usr/local/cuda/lib64:/opt/conda/lib" >> /root/.bashrc
echo "export PATH=/opt/conda/bin:$PATH" >> /root/.bashrc

# Start SSH service
service ssh restart

# Verify SSH is running
if pgrep sshd > /dev/null; then
    echo "SSH server started successfully"
else
    echo "Failed to start SSH server"
    exit 1
fi