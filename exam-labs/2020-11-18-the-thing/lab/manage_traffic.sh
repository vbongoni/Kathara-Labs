#!/bin/bash

# Traffic Daemon Manager for Kathara Lab
# Controls traffic_daemon.sh across all containers
# Usage: manage_traffic.sh [start|stop|status|logs]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS=("r11" "r12" "r21" "r31" "b012" "b02" "b03")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

show_usage() {
    echo "Traffic Daemon Manager"
    echo "======================"
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  start [interval]  Start traffic daemon on all containers (default: 30s)"
    echo "  stop              Stop traffic daemon on all containers"
    echo "  status            Show daemon status on all containers"
    echo "  logs [lines]      Show recent traffic events from centralized log"
    echo "  monitor           Monitor traffic events in real-time"
    echo ""
    echo "Examples:"
    echo "  $0 start          # Start with 30s interval"
    echo "  $0 start 60       # Start with 60s interval"
    echo "  $0 stop           # Stop all daemons"
    echo "  $0 status         # Check status"
    echo "  $0 logs 50        # Show last 50 traffic events"
    echo "  $0 monitor        # Real-time monitoring"
}

# Check if lab is running
check_lab() {
    if ! kathara linfo >/dev/null 2>&1; then
        echo -e "${RED}Error: Kathara lab not running${NC}"
        echo "Start the lab first: kathara lstart"
        exit 1
    fi
}

# Start daemon on all containers
start_daemons() {
    local interval="${1:-30}"
    echo -e "${CYAN}Starting traffic daemons (interval: ${interval}s)...${NC}"
    echo ""

    local started=0
    local failed=0

    for container in "${CONTAINERS[@]}"; do
        if kathara exec "$container" -- test -f /shared/traffic_daemon.sh 2>/dev/null; then
            # Set interval and start daemon
            if kathara exec "$container" -- bash -c "TRAFFIC_INTERVAL=$interval /shared/traffic_daemon.sh start" 2>/dev/null; then
                echo -e "${GREEN}✓${NC} $container - daemon started"
                started=$((started + 1))
            else
                echo -e "${YELLOW}⚠${NC} $container - may already be running"
                started=$((started + 1))
            fi
        else
            echo -e "${RED}✗${NC} $container - script not found"
            failed=$((failed + 1))
        fi
    done

    echo ""
    echo -e "${GREEN}Started: $started${NC} | ${RED}Failed: $failed${NC}"
    echo ""
    echo "Monitor traffic with: $0 monitor"
}

# Stop daemon on all containers
stop_daemons() {
    echo -e "${CYAN}Stopping traffic daemons...${NC}"
    echo ""

    local stopped=0

    for container in "${CONTAINERS[@]}"; do
        if kathara exec "$container" -- /shared/traffic_daemon.sh stop 2>/dev/null; then
            echo -e "${GREEN}✓${NC} $container - daemon stopped"
            stopped=$((stopped + 1))
        else
            echo -e "${YELLOW}⚠${NC} $container - was not running"
        fi
    done

    echo ""
    echo -e "${GREEN}Stopped: $stopped${NC}"
}

# Show status on all containers
show_status() {
    echo -e "${CYAN}Traffic Daemon Status${NC}"
    echo "====================="
    echo ""

    for container in "${CONTAINERS[@]}"; do
        local status=$(kathara exec "$container" -- /shared/traffic_daemon.sh status 2>/dev/null | head -1)
        if echo "$status" | grep -q "running"; then
            local pid=$(echo "$status" | sed -n 's/.*PID: \([0-9]*\).*/\1/p')
            echo -e "${GREEN}●${NC} $container - running (PID: $pid)"
        else
            echo -e "${RED}○${NC} $container - stopped"
        fi
    done

    echo ""
}

# Show recent logs
show_logs() {
    local lines="${1:-30}"
    local log_dir="$SCRIPT_DIR/shared/syslogs"
    local today=$(date '+%Y-%m-%d')
    local log_file="$log_dir/syslog-${today}.log"

    echo -e "${CYAN}Recent Traffic Events (last $lines)${NC}"
    echo "===================================="

    if [ -f "$log_file" ]; then
        # Filter for traffic daemon events
        grep -E '%PING|%LINEPROTO|%ROUTING|%OSPF|%BGP|%ISIS|%ARP|%SYS.*DAEMON|%LINK|%NETWORK' "$log_file" | tail -n "$lines"
    else
        echo "No log file found for today: $log_file"
        echo "Make sure the lab is running and generating traffic."
    fi
}

# Monitor logs in real-time
monitor_logs() {
    local log_dir="$SCRIPT_DIR/shared/syslogs"
    local today=$(date '+%Y-%m-%d')
    local log_file="$log_dir/syslog-${today}.log"

    echo -e "${CYAN}Monitoring Traffic Events (Ctrl+C to stop)${NC}"
    echo "==========================================="

    if [ ! -f "$log_file" ]; then
        touch "$log_file"
    fi

    # Tail and filter for traffic events
    tail -f "$log_file" | grep --line-buffered -E '%PING|%LINEPROTO|%ROUTING|%OSPF|%BGP|%ISIS|%ARP|%SYS|%LINK|%NETWORK' | while read line; do
        # Color code by severity
        if echo "$line" | grep -qE '%[A-Z]+-[34]-'; then
            echo -e "${YELLOW}$line${NC}"
        elif echo "$line" | grep -qE '%[A-Z]+-[12]-'; then
            echo -e "${RED}$line${NC}"
        else
            echo -e "${GREEN}$line${NC}"
        fi
    done
}

# Sync logs from containers
sync_logs() {
    echo -e "${CYAN}Syncing logs from containers...${NC}"
    local today=$(date '+%Y-%m-%d')
    local log_dir="$SCRIPT_DIR/shared/syslogs"
    mkdir -p "$log_dir"

    for container in "${CONTAINERS[@]}"; do
        kathara exec "$container" -- cat "/shared/syslogs/syslog-${today}.log" 2>/dev/null >> "$log_dir/syslog-${today}.log.tmp" 2>/dev/null || true
    done

    if [ -f "$log_dir/syslog-${today}.log.tmp" ]; then
        # Merge and deduplicate
        cat "$log_dir/syslog-${today}.log" "$log_dir/syslog-${today}.log.tmp" 2>/dev/null | sort -u > "$log_dir/syslog-${today}.log.new"
        mv "$log_dir/syslog-${today}.log.new" "$log_dir/syslog-${today}.log"
        rm -f "$log_dir/syslog-${today}.log.tmp"
        echo -e "${GREEN}✓ Logs synced${NC}"
    fi
}

# Main command handling
case "${1:-help}" in
    start)
        check_lab
        start_daemons "$2"
        ;;
    stop)
        check_lab
        stop_daemons
        ;;
    status)
        check_lab
        show_status
        ;;
    logs)
        sync_logs
        show_logs "$2"
        ;;
    monitor)
        sync_logs
        monitor_logs
        ;;
    sync)
        check_lab
        sync_logs
        ;;
    *)
        show_usage
        ;;
esac
