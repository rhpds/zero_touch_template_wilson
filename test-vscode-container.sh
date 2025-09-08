#!/bin/bash

# Local VS Code Container Test Script
# This simulates what AgnosticD would do with the container

set -e

CONTAINER_NAME="vscode-test"
PASSWORD="testpassword123"
PORT="8080"

echo "🚀 Starting VS Code Container Test..."

# Clean up any existing test container
echo "🧹 Cleaning up any existing test container..."
podman rm -f $CONTAINER_NAME 2>/dev/null || true

# Create volumes (simulating emptyDir)
echo "📂 Creating test volumes..."
podman volume rm vscode-workspace-data vscode-config-data 2>/dev/null || true
podman volume create vscode-workspace-data
podman volume create vscode-config-data

# Start container (simulating AgnosticD container creation)
echo "🐳 Starting container with base image..."
# Note: Using exact same image as AgnosticD deployment
podman run -d \
  --name $CONTAINER_NAME \
  --publish $PORT:8080 \
  --env PASSWORD="$PASSWORD" \
  --env RHEL_USER="rhel" \
  --env SSH_PRIVATE_KEY="" \
  --env SSH_PUBLIC_KEY="" \
  --volume vscode-workspace-data:/opt/app-root/src/workspace \
  --volume vscode-config-data:/opt/app-root/src/.local \
  registry.redhat.io/ubi9/ubi:latest \
  /bin/bash -c "tail -f /dev/null"

echo "⏳ Waiting for container to be ready..."
sleep 3

# Execute setup commands (simulating AgnosticD commands execution)
echo "🔧 Executing setup commands..."

echo "  📦 Installing dependencies..."
podman exec $CONTAINER_NAME dnf install -y git openssh-clients

echo "  💻 Installing code-server (binary method)..."
# Direct binary installation (more reliable than npm)
podman exec $CONTAINER_NAME bash -c '
  curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/usr/local
  ln -sf /usr/local/bin/code-server /usr/bin/code-server
'
echo "    ✅ code-server installed via direct binary"

echo "  👤 Creating coder user..."
podman exec $CONTAINER_NAME useradd -u 1001 -g 0 -m coder || true

echo "  📁 Setting up directories..."
podman exec $CONTAINER_NAME mkdir -p /opt/app-root/src/workspace
podman exec $CONTAINER_NAME mkdir -p /opt/app-root/src/.local/share/code-server

echo "  🔐 Setting permissions..."
podman exec $CONTAINER_NAME chown -R coder:root /opt/app-root/src

echo "  📥 Cloning repository..."
podman exec $CONTAINER_NAME bash -c "cd /opt/app-root/src/workspace && git clone https://github.com/rhpds/zero_touch_template_wilson.git"

echo "  🌿 Creating development branch..."
podman exec $CONTAINER_NAME bash -c "cd /opt/app-root/src/workspace/zero_touch_template_wilson && git checkout -b lab-development"

echo "  ⚙️ Configuring Git..."
podman exec $CONTAINER_NAME git config --global user.name 'Lab Developer'
podman exec $CONTAINER_NAME git config --global user.email 'developer@lab.local'

echo "  🔧 Creating code-server config (AgnosticD pattern)..."
podman exec $CONTAINER_NAME mkdir -p /home/coder/.config/code-server

# Create config file with password (matches AgnosticD approach)
podman exec $CONTAINER_NAME bash -c "cat > /home/coder/.config/code-server/config.yaml << 'EOF'
bind-addr: 0.0.0.0:8080
auth: password
password: $PASSWORD
cert: false
EOF"

podman exec $CONTAINER_NAME chown -R coder:root /home/coder/.config

echo "  🔐 Setting up SSH keys for lab-server connection..."
podman exec $CONTAINER_NAME mkdir -p /home/coder/.ssh

# Note: In production, AgnosticD provides SSH keys via environment variables
echo "    ℹ️  SSH keys provided by AgnosticD via environment variables in production"
echo "    ℹ️  Local test uses empty SSH_PRIVATE_KEY and SSH_PUBLIC_KEY (manual SSH available)"

podman exec $CONTAINER_NAME bash -c "cat > /home/coder/.ssh/config << 'EOF'
Host lab-server
    HostName lab-server
    User root
    Port 22
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF"

podman exec $CONTAINER_NAME chown coder:root /home/coder/.ssh/config
podman exec $CONTAINER_NAME chmod 600 /home/coder/.ssh/config

echo "  ⚙️ Creating VS Code SSH integration..."
podman exec $CONTAINER_NAME mkdir -p /opt/app-root/src/workspace/zero_touch_template_wilson/.vscode

podman exec $CONTAINER_NAME bash -c "cat > /opt/app-root/src/workspace/zero_touch_template_wilson/.vscode/settings.json << 'EOF'
{
    \"terminal.integrated.profiles.linux\": {
        \"SSH to Lab Server\": {
            \"path\": \"ssh\",
            \"args\": [\"lab-server\"]
        }
    },
    \"terminal.integrated.defaultProfile.linux\": \"SSH to Lab Server\",
    \"remote.SSH.remotePlatform\": {
        \"lab-server\": \"linux\"
    },
    \"remote.SSH.connectTimeout\": 15
}
EOF"

podman exec $CONTAINER_NAME bash -c "cat > /opt/app-root/src/workspace/zero_touch_template_wilson/.vscode/extensions.json << 'EOF'
{
    \"recommendations\": [
        \"ms-vscode-remote.remote-ssh\",
        \"ms-vscode-remote.remote-ssh-edit\",
        \"redhat.vscode-yaml\",
        \"yzhang.markdown-all-in-one\"
    ]
}
EOF"

podman exec $CONTAINER_NAME chown -R coder:root /opt/app-root/src/workspace/zero_touch_template_wilson/.vscode

echo "    ℹ️  Note: SSH connection to 'lab-server' configured but not available in local test"

echo "  🎛️ Creating VS Code supervisor script..."
podman exec $CONTAINER_NAME bash -c "cat > /tmp/vscode-supervisor.sh << 'EOF'
#!/bin/bash
echo \"VS Code Supervisor starting...\"
while true; do
  echo \"\$(date): Starting code-server\"
  cd /opt/app-root/src/workspace/zero_touch_template_wilson
  su - coder -c 'code-server --config /home/coder/.config/code-server/config.yaml --user-data-dir /opt/app-root/src/.local/share/code-server .'
  echo \"\$(date): code-server exited, restarting in 5 seconds...\"
  sleep 5
done
EOF"

echo "  🚀 Starting VS Code supervisor..."
podman exec $CONTAINER_NAME chmod +x /tmp/vscode-supervisor.sh
podman exec $CONTAINER_NAME bash -c "nohup /tmp/vscode-supervisor.sh > /tmp/code-server.log 2>&1 &"

echo "⏳ Waiting for VS Code to start..."
sleep 10

# Test VS Code accessibility
echo "🧪 Testing VS Code server..."
if curl -s -f http://localhost:$PORT > /dev/null; then
    echo "✅ VS Code server is responding!"
else
    echo "❌ VS Code server is not responding"
    echo "📋 Checking logs..."
    podman exec $CONTAINER_NAME tail -20 /tmp/code-server.log
fi

echo ""
echo "🎉 Container test setup complete!"
echo ""
echo "📋 Test Results:"
echo "  🌐 VS Code URL: http://localhost:$PORT"
echo "  🔑 Password: $PASSWORD"
echo "  📂 Workspace: /opt/app-root/src/workspace/zero_touch_template_wilson"
echo ""
echo "🔍 Debugging commands:"
echo "  podman exec -it $CONTAINER_NAME /bin/bash"
echo "  podman exec $CONTAINER_NAME tail -f /tmp/code-server.log"
echo "  podman exec $CONTAINER_NAME ps aux"
echo ""
echo "🧹 Cleanup when done:"
echo "  podman rm -f $CONTAINER_NAME"
echo "  podman volume rm vscode-workspace-data vscode-config-data"
echo ""

# Show final status
echo "📊 Container Status:"
podman ps --filter name=$CONTAINER_NAME

# Show process status
echo ""
echo "🏃 Running Processes:"
podman exec $CONTAINER_NAME ps aux | grep -E "(code-server|supervisor|tail)" || echo "  No VS Code processes found"

echo ""
echo "✨ Open http://localhost:$PORT in your browser to test VS Code!"
