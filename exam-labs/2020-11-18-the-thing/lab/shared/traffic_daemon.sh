#!/bin/bash

# Traffic Daemon for Kathara Lab
# Generates continuous network traffic and syslog events
# Usage: traffic_daemon.sh [start|stop|status|run]

# Configuration
INTERVAL=${TRAFFIC_INTERVAL:-60}        # Base interval in seconds
LOG_LEVEL=${LOG_LEVEL:-info}            # info, debug, verbose
PID_FILE="/tmp/traffic_daemon.pid"
DAEMON_LOG="/var/log/traffic_daemon.log"

# Get device identity
HOSTNAME=$(hostname)
DEVICE_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || hostname -I | awk '{print $1}')

# Discover peer IPs from interfaces
discover_peers() {
    local peers=()
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^eth[0-9]+$'); do
        local network=$(ip -o -4 addr show "$iface" 2>/dev/null | awk '{print $4}')
        if [ -n "$network" ]; then
            local base=$(echo "$network" | cut -d'/' -f1 | sed 's/\.[0-9]*$/./')
            # Add common peer addresses in the same subnet
            for i in 1 2 3 10 11 12 20 21 30 31; do
                local peer="${base}${i}"
                if [ "$peer" != "$DEVICE_IP" ]; then
                    peers+=("$peer")
                fi
            done
        fi
    done
    # Remove duplicates and return
    echo "${peers[@]}" | tr ' ' '\n' | sort -u | head -10
}

# Log event using net_logger
log_event() {
    local tag="$1"
    local message="$2"

    if [ -x /usr/local/bin/net_logger ]; then
        /usr/local/bin/net_logger -t "$tag" "$message"
    elif [ -x /usr/local/bin/log_network_event ]; then
        /usr/local/bin/log_network_event "system" "$message"
    else
        logger -t "$tag" "$message" 2>/dev/null || echo "$(date '+%b %d %H:%M:%S') $DEVICE_IP: $message" >> /var/log/syslog
    fi
}

# Connectivity check - ping peers
check_connectivity() {
    local peers=($(discover_peers))
    local checked=0

    for peer in "${peers[@]}"; do
        if [ $checked -ge 3 ]; then break; fi  # Limit to 3 peers per cycle

        local result=$(ping -c 1 -W 1 "$peer" 2>/dev/null)
        if [ $? -eq 0 ]; then
            local latency=$(echo "$result" | grep -oP 'time=\K[0-9.]+' | head -1)
            latency=${latency:-1}

            if (( $(echo "$latency > 100" | bc -l 2>/dev/null || echo 0) )); then
                log_event "NETWORK" "%PING-4-LATENCY: High latency to $peer (${latency}ms)"
            else
                log_event "NETWORK" "%PING-6-REACHABLE: Host $peer is reachable (${latency}ms)"
            fi
        else
            log_event "NETWORK" "%PING-3-UNREACHABLE: Host $peer is unreachable"
        fi
        checked=$((checked + 1))
    done
}

# Interface statistics
log_interface_stats() {
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^eth[0-9]+$'); do
        local stats=$(ip -s link show "$iface" 2>/dev/null)
        local rx_bytes=$(echo "$stats" | awk '/RX:/{getline; print $1}')
        local tx_bytes=$(echo "$stats" | awk '/TX:/{getline; print $1}')
        local rx_errors=$(echo "$stats" | awk '/RX:/{getline; print $3}')
        local tx_errors=$(echo "$stats" | awk '/TX:/{getline; print $3}')

        rx_bytes=${rx_bytes:-0}
        tx_bytes=${tx_bytes:-0}
        rx_errors=${rx_errors:-0}
        tx_errors=${tx_errors:-0}

        local state=$(ip link show "$iface" 2>/dev/null | grep -oP 'state \K\w+')

        if [ "$rx_errors" -gt 0 ] || [ "$tx_errors" -gt 0 ]; then
            log_event "INTERFACE" "%LINEPROTO-4-ERRORS: $iface errors detected RX_err:$rx_errors TX_err:$tx_errors"
        else
            log_event "INTERFACE" "%LINEPROTO-6-STATS: $iface state:$state RX:$rx_bytes TX:$tx_bytes errors:0"
        fi
    done
}

# Routing information
log_routing_info() {
    local route_count=$(ip route | wc -l)
    local default_gw=$(ip route | grep default | awk '{print $3}' | head -1)

    if [ -n "$default_gw" ]; then
        log_event "ROUTING" "%ROUTING-6-INFO: $route_count routes active, default via $default_gw"
    else
        log_event "ROUTING" "%ROUTING-5-INFO: $route_count routes active, no default gateway"
    fi

    # Check for route changes (compare with last snapshot)
    local current_routes=$(ip route | md5sum | awk '{print $1}')
    local last_routes_file="/tmp/last_routes_hash"

    if [ -f "$last_routes_file" ]; then
        local last_routes=$(cat "$last_routes_file")
        if [ "$current_routes" != "$last_routes" ]; then
            log_event "ROUTING" "%ROUTING-5-UPDATE: Routing table changed"
        fi
    fi
    echo "$current_routes" > "$last_routes_file"
}

# Simulate protocol keepalives
simulate_keepalive() {
    local protocols=("OSPF" "BGP" "ISIS")
    local protocol=${protocols[$((RANDOM % ${#protocols[@]}))]}

    case $protocol in
        OSPF)
            log_event "OSPF" "%OSPF-6-HELLO: Sent hello on eth0 to 224.0.0.5, area 0.0.0.0"
            ;;
        BGP)
            local peer_as=$((65000 + RANDOM % 100))
            log_event "BGP" "%BGP-6-KEEPALIVE: Keepalive sent to neighbor AS$peer_as"
            ;;
        ISIS)
            log_event "ISIS" "%ISIS-6-HELLO: IS-IS Level-1 hello sent on eth0"
            ;;
    esac
}

# Random network events
random_event() {
    local rand=$((RANDOM % 100))

    if [ $rand -lt 5 ]; then
        # 5% chance - Warning event
        local events=(
            "%SYS-4-WARN: Memory utilization at $((60 + RANDOM % 30))%"
            "%SYS-4-WARN: CPU spike detected, current load: 0.$((RANDOM % 99))"
            "%LINK-4-FLAP: Interface eth$((RANDOM % 3)) experiencing instability"
            "%SYS-4-WARN: ARP table nearly full, $((200 + RANDOM % 50)) entries"
        )
        log_event "SYSTEM" "${events[$((RANDOM % ${#events[@]}))]}"
    elif [ $rand -lt 10 ]; then
        # 5% chance - Info event
        local events=(
            "%SYS-6-INFO: Configuration autosave completed"
            "%SYS-6-INFO: NTP synchronized with upstream server"
            "%SYS-6-INFO: Neighbor discovery completed on eth0"
        )
        log_event "SYSTEM" "${events[$((RANDOM % ${#events[@]}))]}"
    fi
}

# ARP activity
log_arp_activity() {
    local arp_count=$(ip neigh | grep -c REACHABLE 2>/dev/null || echo 0)
    local stale_count=$(ip neigh | grep -c STALE 2>/dev/null || echo 0)

    if [ "$stale_count" -gt 5 ]; then
        log_event "ARP" "%ARP-4-STALE: $stale_count stale ARP entries detected"
    else
        log_event "ARP" "%ARP-6-INFO: ARP table: $arp_count reachable, $stale_count stale"
    fi
}

# Main daemon loop
run_daemon() {
    echo "$(date): Traffic daemon started on $HOSTNAME ($DEVICE_IP)" >> "$DAEMON_LOG"
    log_event "SYSTEM" "%SYS-5-DAEMON: Traffic monitoring daemon started"

    local cycle=0
    while true; do
        cycle=$((cycle + 1))

        # Every cycle (30s default)
        check_connectivity

        # Every 2 cycles (60s)
        if [ $((cycle % 2)) -eq 0 ]; then
            log_interface_stats
            simulate_keepalive
        fi

        # Every 4 cycles (2min)
        if [ $((cycle % 4)) -eq 0 ]; then
            log_routing_info
            log_arp_activity
        fi

        # Random events check every cycle
        random_event

        # Reset cycle counter
        if [ $cycle -ge 120 ]; then
            cycle=0
            log_event "SYSTEM" "%SYS-6-INFO: Traffic daemon heartbeat - running normally"
        fi

        sleep "$INTERVAL"
    done
}

# Start daemon in background
start_daemon() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "Traffic daemon already running (PID: $(cat $PID_FILE))"
        return 1
    fi

    echo "Starting traffic daemon on $HOSTNAME..."
    nohup "$0" run >> "$DAEMON_LOG" 2>&1 &
    echo $! > "$PID_FILE"
    echo "Traffic daemon started (PID: $!)"
    log_event "SYSTEM" "%SYS-5-DAEMON: Traffic daemon started with PID $!"
}

# Stop daemon
stop_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping traffic daemon (PID: $pid)..."
            kill "$pid"
            rm -f "$PID_FILE"
            log_event "SYSTEM" "%SYS-5-DAEMON: Traffic daemon stopped"
            echo "Traffic daemon stopped"
        else
            echo "Traffic daemon not running (stale PID file)"
            rm -f "$PID_FILE"
        fi
    else
        echo "Traffic daemon not running"
    fi
}

# Show status
show_status() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "Traffic daemon is running (PID: $(cat $PID_FILE))"
        echo "Interval: ${INTERVAL}s"
        echo "Log: $DAEMON_LOG"
        if [ -f "$DAEMON_LOG" ]; then
            echo "Recent activity:"
            tail -5 "$DAEMON_LOG"
        fi
    else
        echo "Traffic daemon is not running"
    fi
}

# Command handling
case "${1:-run}" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    status)
        show_status
        ;;
    run)
        run_daemon
        ;;
    *)
        echo "Usage: $0 [start|stop|status|run]"
        echo "  start  - Start daemon in background"
        echo "  stop   - Stop running daemon"
        echo "  status - Show daemon status"
        echo "  run    - Run in foreground (default)"
        exit 1
        ;;
esac
