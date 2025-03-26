#!/bin/bash

echo "* soft nofile 32768" >> /etc/security/limits.conf
echo "* hard nofile 32768" >> /etc/security/limits.conf
echo "root soft nofile 32768" >> /etc/security/limits.conf
echo "root hard nofile 32768" >> /etc/security/limits.conf

# Detect private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "Setting up Valkey node ${node_index + 1} with detected private IP $PRIVATE_IP"
apt-get update
apt-get install -y build-essential tcl git dnsutils

# Install Valkey from pre-built package
echo "Installing Valkey from pre-built package..."
cd /tmp
curl -L https://download.valkey.io/releases/valkey-8.0.2-focal-x86_64.tar.gz -o valkey.tar.gz
tar -xzf valkey.tar.gz
cd valkey-8.0.2-focal-x86_64
cp -a bin/* /usr/bin/

# Create Valkey service user
useradd -r -s /bin/false valkey

# Create necessary directories
mkdir -p /run/valkey
mkdir -p /etc/valkey
mkdir -p /var/lib/valkey
chown valkey:valkey /var/lib/valkey
chown valkey:valkey /run/valkey
chown valkey:valkey /etc/valkey

# Configure Valkey
cat > /etc/valkey/valkey.conf <<EOF
# Valkey configuration
port 6379
daemonize yes
supervised systemd
pidfile /var/run/valkey/valkey-server.pid
logfile /var/log/valkey/valkey-server.log
dir /var/lib/valkey
bind 0.0.0.0
protected-mode no

# Cluster specific configuration
cluster-enabled yes
cluster-config-file /etc/valkey/nodes.conf
cluster-node-timeout 5000
appendonly yes
EOF

# Create log directory
mkdir -p /var/log/valkey
chown valkey:valkey /var/log/valkey

# Create pid directory
mkdir -p /var/run/valkey
chown valkey:valkey /var/run/valkey

# Set up systemd service
cat > /etc/systemd/system/valkey.service <<EOF
[Unit]
Description=Advanced key-value store
After=network.target
Documentation=https://valkey.io/docs/, man:valkey-server(1)

[Service]
Type=simple
ExecStart=/usr/bin/valkey-server /etc/valkey/valkey.conf --supervised systemd --daemonize no
PIDFile=/run/valkey/valkey-server.pid
TimeoutStopSec=0
Restart=always
User=valkey
Group=valkey
RuntimeDirectory=valkey
RuntimeDirectoryMode=2755

UMask=007
PrivateTmp=true
LimitNOFILE=65535
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=-/var/lib/valkey
ReadWritePaths=-/var/log/valkey
ReadWritePaths=-/var/run/valkey

CapabilityBoundingSet=
LockPersonality=true
MemoryDenyWriteExecute=true
NoNewPrivileges=true
PrivateUsers=true
ProtectClock=true
ProtectControlGroups=true
ProtectHostname=true
ProtectKernelLogs=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectProc=invisible
RemoveIPC=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~ @privileged @resources

# valkey-server can write to its own config file when in cluster mode so we
# permit writing there by default. If you are not using this feature, it is
# recommended that you remove this line.
ReadWriteDirectories=-/etc/valkey

# This restricts this service from executing binaries other than valkey-server
# itself. This is really effective at e.g. making it impossible to an
# attacker to spawn a shell on the system, but might be more restrictive
# than desired. If you need to, you can permit the execution of extra
# binaries by adding an extra ExecPaths= directive with the command
# systemctl edit valkey-server.service
NoExecPaths=/
ExecPaths=/usr/bin/valkey-server /usr/lib /lib

[Install]
WantedBy=multi-user.target
Alias=valkey.service
EOF

# Enable and start Valkey service
systemctl daemon-reload
systemctl enable valkey
systemctl start valkey

# Sleep to ensure all nodes are up before creating cluster
sleep 30

# Write node index and IP to a file for use in cluster creation
echo "${node_index}:$PRIVATE_IP" > /tmp/node_info

echo "Valkey node ${node_index + 1} setup complete"


# Initialize the cluster from the first node
if [ ${node_index} -eq 0 ]; then
  echo "Initializing Valkey cluster from first node..."
  # Wait for other nodes to be ready
  sleep 60

  # Ping other nodes to ensure they're up
  for i in {1..10}; do
    echo "Attempt $i: Checking if other nodes are reachable..."
    NODE2_REACHABLE=$(ping -c 1 10.10.10.2 >/dev/null 2>&1 && echo "yes" || echo "no")
    NODE2_REACHABLE=$(ping -c 1 10.10.10.3 >/dev/null 2>&1 && echo "yes" || echo "no")
    NODE3_REACHABLE=$(ping -c 1 10.10.10.4 >/dev/null 2>&1 && echo "yes" || echo "no")

    echo "Node 2 (10.10.10.3) reachable: $NODE2_REACHABLE"
    echo "Node 3 (10.10.10.4) reachable: $NODE3_REACHABLE"

    if [ "$NODE2_REACHABLE" = "yes" ] && [ "$NODE3_REACHABLE" = "yes" ]; then
      echo "All nodes are reachable. Creating cluster with known IPs..."
      /usr/bin/valkey-cli --cluster create ${join(" ", node_ips)} --cluster-replicas 0 --cluster-yes
      break
    else
      echo "Not all nodes are reachable yet. Waiting 10 seconds..."
      sleep 10
    fi
  done
fi

echo "Valkey node ${node_index + 1} setup complete"
