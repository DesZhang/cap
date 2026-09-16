#!/bin/bash
# ── Cap Offline — Mock Redis Cluster for smoke testing ─────
#
# Spins up a local 3-node Redis cluster on host ports 17000–17002
# using the locally installed redis-server CLI.
#
# Usage: bash mock-redis-cluster.sh {start|stop|restart} [HOST_IP]
#
# HOST_IP is the IP address the cluster nodes should advertise.
# If omitted, auto-detected from the primary network interface.

set -euo pipefail

PORTS=(17000 17001 17002)
CLUSTER_DIR="/tmp/cap-redis-cluster"

# Auto-detect host IP if not provided
if [ "${2:-}" ]; then
  HOST_IP="$2"
else
  HOST_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')"
fi

start() {
  echo "Using host IP: $HOST_IP"
  mkdir -p "$CLUSTER_DIR"

  for port in "${PORTS[@]}"; do
    mkdir -p "$CLUSTER_DIR/$port"
    if redis-cli -p "$port" ping >/dev/null 2>&1; then
      echo "Port $port already in use, skipping..."
      continue
    fi
    redis-server \
      --port "$port" \
      --bind 0.0.0.0 \
      --cluster-enabled yes \
      --cluster-config-file "$CLUSTER_DIR/$port/nodes.conf" \
      --cluster-node-timeout 5000 \
      --cluster-announce-ip "$HOST_IP" \
      --cluster-announce-port "$port" \
      --cluster-announce-bus-port "$((port + 10000))" \
      --protected-mode no \
      --dir "$CLUSTER_DIR/$port" \
      --daemonize yes \
      --loglevel warning
  done

  sleep 1

  # Form the cluster (no replicas)
  redis-cli --cluster create \
    "${HOST_IP}:17000" \
    "${HOST_IP}:17001" \
    "${HOST_IP}:17002" \
    --cluster-replicas 0 \
    --cluster-yes

  echo "Redis cluster ready on ${HOST_IP} ports ${PORTS[*]}"
}

stop() {
  for port in "${PORTS[@]}"; do
    # Graceful shutdown first
    redis-cli -p "$port" shutdown nosave 2>/dev/null || true
  done

  sleep 1

  # Force-kill anything still listening on our ports
  for port in "${PORTS[@]}"; do
    local pids
    pids="$(lsof -t -iTCP:"$port" 2>/dev/null || true)"
    if [ -n "$pids" ]; then
      echo "Force-killing PID(s) $pids on port $port"
      kill -9 $pids 2>/dev/null || true
    fi
  done

  rm -rf "$CLUSTER_DIR"

  # Verify all ports are free
  local leftover=0
  for port in "${PORTS[@]}"; do
    if lsof -Pi :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "WARNING: port $port is still in use after cleanup"
      leftover=1
    fi
  done

  if [ "$leftover" -eq 0 ]; then
    echo "Redis cluster stopped and ports freed"
  else
    echo "Redis cluster stopped (some ports may still be bound)"
  fi
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  *) echo "Usage: $0 {start|stop|restart} [HOST_IP]"; exit 1 ;;
esac
