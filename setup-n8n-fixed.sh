#!/bin/bash

# Create persistent data directory
sudo mkdir -p /home/n8n-data
sudo chmod 777 /home/n8n-data

# Stop current n8n container
sudo docker stop n8n 2>/dev/null || true
sudo docker rm n8n 2>/dev/null || true

# Create startup script with persistent volume
cat > /tmp/startup.sh << 'EOFMARKER'
#!/bin/bash

# Function to start n8n container with persistent storage
start_n8n() {
  # Check if n8n container is running
  if docker ps -q --filter "name=n8n" | grep -q .; then
    echo "n8n is already running - no action needed"
    return 0
  fi

  # Check if container exists but is stopped
  if docker ps -a -q --filter "name=n8n" | grep -q .; then
    echo "n8n container exists but is not running - starting it..."
    docker start n8n
    echo "n8n restarted at $(date)"
    return 0
  fi

  # No container exists, create a new one
  echo "Starting new n8n container with persistent storage..."
  docker rm -f n8n 2>/dev/null || true
  docker run -d \
    --restart always \
    --name n8n \
    -p 5678:5678 \
    -v /home/n8n-data:/home/node/.n8n \
    -m 900m \
    --memory-swap 2G \
    -e NODE_OPTIONS="--max_old_space_size=384" \
    -e N8N_DISABLE_PRODUCTION_MAIN_PROCESS="true" \
    -e N8N_DISABLE_WORKFLOW_STATS="true" \
    -e N8N_PROTOCOL="https" \
    -e GENERIC_TIMEZONE="UTC" \
    -e WEBHOOK_URL="https://auto8i.serveo.net/" \
    -e N8N_HOST="auto8i.serveo.net" \
    n8nio/n8n:1.91.2
  echo "New n8n container started at $(date) with persistent storage"
}

# Function to start serveo tunnel
start_serveo() {
  # Check if serveo tunnel is already running
  if pgrep -f "ssh -R auto8i.serveo.net:80:localhost:5678" > /dev/null; then
    echo "Serveo tunnel is already running - no action needed"
    return 0
  fi

  # Start a new serveo tunnel
  echo "Starting serveo tunnel..."
  autossh -M 0 -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -o "StrictHostKeyChecking=no" -R "auto8i.serveo.net:80:localhost:5678" serveo.net &
  echo "Serveo tunnel started at $(date)"
}

# Main monitoring loop
while true; do
  # Log timestamp for monitoring
  echo "--- Monitoring check at $(date) ---"

  # Check and start services if needed
  start_n8n
  start_serveo

  # Wait before next check
  echo "Sleeping for 60 seconds before next check..."
  sleep 60
done
EOFMARKER

# Install updated script
sudo mv /tmp/startup.sh /usr/local/bin/startup.sh
sudo chmod +x /usr/local/bin/startup.sh

# Restart services
sudo systemctl restart always-running.service 2>/dev/null || echo "Warning: always-running.service not found or failed to restart"
sudo systemctl restart monitor.service 2>/dev/null || echo "Warning: monitor.service not found or failed to restart"

# Run startup script to apply changes immediately
sudo /usr/local/bin/startup.sh

echo "n8n persistent storage has been set up at /home/n8n-data"
echo "Your workflows and data will now persist across restarts"
echo "To verify the volume mount:"
echo "  - Docker: sudo docker inspect n8n | grep -A 10 Mounts"
