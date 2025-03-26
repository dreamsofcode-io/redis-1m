#!/bin/bash

echo "* soft nofile 32768" >> /etc/security/limits.conf
echo "* hard nofile 32768" >> /etc/security/limits.conf
echo "root soft nofile 32768" >> /etc/security/limits.conf
echo "root hard nofile 32768" >> /etc/security/limits.conf

# Wait for private network to be available
echo "Waiting for network interfaces to be ready..."
for i in {1..30}; do
  if ip addr show | grep -q "10.0.1"; then
    echo "Private network interface is ready."
    break
  fi
  echo "Waiting for private network interface (attempt $i)..."
  sleep 5
done

# Detect private IP - For Hetzner, we need to handle the network interface naming differently
PRIVATE_IP=$(ip -4 addr | grep -oP '10\.0\.1\.\d+' | head -1)
echo "Setting up Valkey node ${node_index + 1} with detected private IP $PRIVATE_IP"

# Install required packages
apt-get update
apt-get install -y build-essential tcl git dnsutils curl

# Install Valkey from pre-built package
echo "Installing Valkey from pre-built package..."
cd /tmp
curl -L https://download.valkey.io/releases/valkey-8.0.2-focal-x86_64.tar.gz -o valkey.tar.gz
tar -xzf valkey.tar.gz
cd valkey-8.0.2-focal-x86_64
cp -a bin/* /usr/bin/

# Create Valkey service user
useradd -r -s /bin/false valkey

# Define the ports for Valkey instances
VALKEY_PORTS="${valkey_ports}"

# Add more ports here if needed, for example:
# VALKEY_PORTS=(6379 7000 7001)

# Create base directories
mkdir -p /run/valkey
mkdir -p /var/log/valkey
mkdir -p /var/run/valkey
chown valkey:valkey /run/valkey
chown valkey:valkey /var/log/valkey
chown valkey:valkey /var/run/valkey

# Loop through each port and set up a Valkey instance
for PORT in $VALKEY_PORTS; do
  echo "Setting up Valkey instance on port $PORT..."

  # Create instance-specific directories
  mkdir -p "/etc/valkey/$PORT"
  mkdir -p "/var/lib/valkey/$PORT"
  chown valkey:valkey "/etc/valkey/$PORT"
  chown valkey:valkey "/var/lib/valkey/$PORT"

  # Configure Valkey instance
  cat > "/etc/valkey/$PORT/valkey.conf" <<EOF
# Valkey configuration for instance $PORT
port $PORT
daemonize yes
supervised systemd
pidfile /var/run/valkey/valkey-server-$PORT.pid
logfile /var/log/valkey/valkey-server-$PORT.log
dir /var/lib/valkey/$PORT
bind 0.0.0.0
protected-mode no

# Cluster specific configuration
cluster-enabled yes
cluster-config-file /etc/valkey/$PORT/nodes.conf
cluster-node-timeout 5000
appendonly yes
EOF

  # Set up systemd service
  cat > "/etc/systemd/system/valkey-$PORT.service" <<EOF
[Unit]
Description=Advanced key-value store (Port $PORT)
After=network.target
Documentation=https://valkey.io/docs/, man:valkey-server(1)

[Service]
Type=simple
ExecStart=/usr/bin/valkey-server /etc/valkey/$PORT/valkey.conf --supervised systemd --daemonize no
PIDFile=/run/valkey/valkey-server-$PORT.pid
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
ReadWritePaths=-/var/lib/valkey/$PORT
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
# permit writing there by default.
ReadWriteDirectories=-/etc/valkey/$PORT

# This restricts this service from executing binaries other than valkey-server
# itself.
NoExecPaths=/
ExecPaths=/usr/bin/valkey-server /usr/lib /lib

[Install]
WantedBy=multi-user.target
Alias=valkey-$PORT.service
EOF

  # Enable and start Valkey service for this instance
  systemctl daemon-reload
  systemctl enable "valkey-$PORT"
  systemctl start "valkey-$PORT"

  echo "Valkey instance on port $PORT setup complete."
done

echo "All Valkey instances have been configured and started."

# Sleep to ensure all nodes are up before creating cluster
sleep 30

# Write node index and IP to a file for use in cluster creation
echo "${node_index}:$PRIVATE_IP" > /tmp/node_info

# Initialize the cluster from the first node
if [ ${node_index} -eq 0 ]; then
  echo "Initializing Valkey cluster from first node..."
  # Wait for other nodes to be ready
  sleep 60

  # Get total number of nodes (should be passed from Terraform)
  NODE_COUNT=${node_count}
  echo "Total number of nodes in cluster: $NODE_COUNT"

  # Ping other nodes to ensure they're up
  for i in {1..15}; do
    echo "Attempt $i: Checking if all nodes are reachable..."

    # Initialize array to track reachable nodes
    declare -a REACHABLE_NODES
    ALL_NODES_REACHABLE=true

    # Check each node
    for j in $(seq 0 $((NODE_COUNT-1))); do
      # Get the IP address for this node (base IP + node number)
      NODE_IP="10.0.1.$((j+2))"

      # Skip checking ourselves
      if [ $j -eq ${node_index} ]; then
        REACHABLE_NODES[$j]="yes"
        continue
      fi

      # Check if node is reachable
      REACHABLE=$(ping -c 1 $NODE_IP >/dev/null 2>&1 && echo "yes" || echo "no")
      REACHABLE_NODES[$j]=$REACHABLE
      echo "Node $((j+1)) $NODE_IP reachable: $REACHABLE"

      # If any node is unreachable, set the flag to false
      if [ "$REACHABLE" = "no" ]; then
        ALL_NODES_REACHABLE=false
      fi
    done

    # If all nodes are reachable, create the cluster
    if [ "$ALL_NODES_REACHABLE" = true ]; then
      echo "All nodes are reachable. Creating cluster with known IPs..."
      # Create the cluster using the node_ips array
      /usr/bin/valkey-cli --cluster create ${join(" ", node_ips)} --cluster-replicas 0 --cluster-yes
      break
    else
      echo "Not all nodes are reachable yet. Waiting 10 seconds..."
      sleep 10
    fi
  done
fi

echo "Valkey node ${node_index + 1} setup complete"
