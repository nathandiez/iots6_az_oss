#!/usr/bin/env bash
# verify-deployment.sh - Verify the deployment is working
set -e

echo "Verifying deployment..."
sleep 5

# Use same IP detection method as SSH provisioner
get_ip() {
  # Method 1: Extract from terraform state directly
  local ip=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.child_modules[].resources[] | select(.type=="proxmox_virtual_environment_vm") | .values.ipv4_addresses[0][0]' 2>/dev/null || echo "")
  
  # Check if it's valid
  if [ -n "$ip" ] && [ "$ip" != "null" ] && [ "$ip" != "127.0.0.1" ]; then
    echo "$ip"
    return 0
  fi
  
  # Method 2: Extract from terraform show text output
  ip=$(terraform show 2>/dev/null | grep -A 5 "ipv4_addresses" | grep -o -E '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '127.0.0.1' | head -n 1)
  
  if [ -n "$ip" ]; then
    echo "$ip"
    return 0
  fi
  
  # Method 3: Try DNS resolution as fallback
  ip=$(ping -c 1 nedv1-iots6.local 2>/dev/null | head -n 1 | grep -o -E '([0-9]{1,3}\.){3}[0-9]{1,3}' || echo "")
  
  if [ -n "$ip" ]; then
    echo "$ip"
    return 0
  fi
  
  echo ""
  return 1
}

IP=$(get_ip)

if [ -n "$IP" ] && [ "$IP" != "127.0.0.1" ]; then
  echo "Testing IoT services at $IP..."
  
  # Test TimescaleDB port
  echo "Testing TimescaleDB connectivity..."
  if nc -z -w5 "$IP" 5432 2>/dev/null; then
    echo "✅ TimescaleDB port 5432 is accessible"
    
    # Test actual database connection
    if ssh -o StrictHostKeyChecking=no -o BatchMode=yes nathan@"$IP" "PGPASSWORD=iotpass psql -h localhost -U iotuser -d iotdb -c 'SELECT 1;'" >/dev/null 2>&1; then
      echo "✅ TimescaleDB database connection successful"
    else
      echo "⚠️  TimescaleDB port is open but database may still be initializing"
    fi
  else
    echo "❌ TimescaleDB port 5432 is not accessible"
  fi
  
  # Test MQTT broker
  echo "Testing MQTT broker connectivity..."
  if nc -z -w5 "$IP" 1883 2>/dev/null; then
    echo "✅ MQTT broker port 1883 is accessible"
  else
    echo "❌ MQTT broker port 1883 is not accessible"
  fi
  
  # Check Docker containers
  echo "Checking Docker container status..."
  echo "---"
  if ssh -o StrictHostKeyChecking=no -o BatchMode=yes nathan@"$IP" "docker ps --format 'table {{.Names}}\t{{.Status}}'" 2>/dev/null; then
    echo "---"
    echo "✅ Container status check successful"
  else
    echo "❌ Could not check container status"
  fi
  
  # Test Docker network
  echo "Checking Docker network..."
  if ssh -o StrictHostKeyChecking=no -o BatchMode=yes nathan@"$IP" "docker network ls | grep -q iot_network" 2>/dev/null; then
    echo "✅ Docker iot_network exists"
  else
    echo "❌ Docker iot_network not found"
  fi
  
  echo ""
  echo "✅ IoT Infrastructure Verification Complete!"
  echo "📡 Service endpoints:"
  echo "   • TimescaleDB: postgresql://iotuser:iotpass@$IP:5432/iotdb"
  echo "   • MQTT Broker: mqtt://$IP:1883"
  echo "   • SSH Access: nathan@$IP"
  echo "✅ Server IP: $IP"
  
else
  echo "❌ Could not determine valid IP for verification"
  exit 1
fi