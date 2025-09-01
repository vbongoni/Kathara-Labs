#!/bin/bash

# Simplified Log Management for Kathara Lab
# Single comprehensive tool for all logging operations

SYSLOG_DIR="/Users/vbongoni/git/dev/Kathara-Labs/exam-labs/2020-11-18-the-thing/lab/syslogs"
CURRENT_DATE=$(date '+%Y-%m-%d')

show_usage() {
    echo "Kathara Lab Centralized Logging Tool"
    echo "===================================="
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  start              Start lab and setup logging"
    echo "  sync               Sync logs from containers to host"
    echo "  monitor            Monitor today's logs in real-time"
    echo "  list               List all available log files"
    echo "  view [DATE]        View log file content"
    echo "  test               Generate test logs"
    echo "  status             Show current status"
    echo "  stop               Stop lab and collect final logs"
    echo "  clean [DAYS]       Remove logs older than DAYS (default: 30)"
    echo ""
    echo "Examples:"
    echo "  $0 start           # Start lab with logging"
    echo "  $0 sync            # Sync container logs to host"
    echo "  $0 monitor         # Watch today's logs"
    echo "  $0 view 2025-08-19 # View specific date logs"
    echo "  $0 test            # Generate test entries"
}

get_log_file() {
    local date="${1:-$CURRENT_DATE}"
    echo "${SYSLOG_DIR}/syslog-${date}.log"
}

start_lab() {
    echo "Starting Kathara lab..."
    kathara lstart
    if [ $? -eq 0 ]; then
        echo "✓ Lab started"
        sleep 3
        test_logs
        sync_logs
        echo "✓ Lab ready! Use '$0 monitor' to watch logs"
    else
        echo "✗ Failed to start lab"
        exit 1
    fi
}

sync_logs() {
    echo "Syncing logs from containers..."
    mkdir -p "$SYSLOG_DIR"
    
    if ! kathara linfo >/dev/null 2>&1; then
        echo "⚠ Lab not running"
        return 1
    fi
    
    containers=("r11" "r12" "b012" "b02" "b03" "r21" "r31")
    
    for container in "${containers[@]}"; do
        if kathara exec "$container" echo "test" >/dev/null 2>&1; then
            kathara exec "$container" cat "/shared/syslogs/syslog-${CURRENT_DATE}.log" 2>/dev/null >> "$SYSLOG_DIR/syslog-${CURRENT_DATE}.log" 2>/dev/null || true
        fi
    done
    
    # Remove duplicates and sort
    if [ -f "$SYSLOG_DIR/syslog-${CURRENT_DATE}.log" ]; then
        sort -u "$SYSLOG_DIR/syslog-${CURRENT_DATE}.log" > "$SYSLOG_DIR/syslog-${CURRENT_DATE}.log.tmp"
        mv "$SYSLOG_DIR/syslog-${CURRENT_DATE}.log.tmp" "$SYSLOG_DIR/syslog-${CURRENT_DATE}.log"
        echo "✓ Logs synced: $(wc -l < "$SYSLOG_DIR/syslog-${CURRENT_DATE}.log") lines"
    else
        echo "⚠ No logs found"
    fi
}

monitor_logs() {
    local log_file=$(get_log_file)
    sync_logs
    echo "Monitoring: $log_file"
    echo "Press Ctrl+C to stop"
    echo "===================="
    touch "$log_file"
    tail -f "$log_file"
}

list_logs() {
    echo "Available log files:"
    echo "==================="
    if ls "${SYSLOG_DIR}"/syslog-[0-9]*.log 2>/dev/null | head -1 > /dev/null; then
        for log_file in "${SYSLOG_DIR}"/syslog-[0-9]*.log; do
            if [ -f "$log_file" ]; then
                filename=$(basename "$log_file")
                size=$(du -h "$log_file" | cut -f1)
                lines=$(wc -l < "$log_file")
                printf "  %-20s %6s (%d lines)\n" "$filename" "$size" "$lines"
            fi
        done
    else
        echo "  No log files found"
    fi
}

view_logs() {
    local date="$1"
    local log_file=$(get_log_file "$date")
    
    if [ -f "$log_file" ]; then
        echo "Viewing: $log_file"
        echo "=================="
        cat "$log_file"
    else
        echo "Log file not found: $log_file"
        exit 1
    fi
}

test_logs() {
    echo "Generating test logs with IP format..."
    
    # Create test logs directly in the correct IP format
    current_date=$(date '+%Y-%m-%d')
    log_file="$SYSLOG_DIR/syslog-${current_date}.log"
    
    # Generate timestamp
    timestamp=$(date '+%b %d %H:%M:%S')
    inner_timestamp=$(date '+%b %d %H:%M:%S')
    millis=$(printf "%03d" $((RANDOM % 1000)))
    
    mkdir -p "$SYSLOG_DIR"
    
    # Generate realistic network logs with IP addresses in the exact format requested
    echo "$timestamp 10.0.0.11 116: *$inner_timestamp.$millis: %OSPF-4-FLOOD_WAR: Process 1 re-originates LSA ID 10.0.5.2 type-2 adv-rtr 10.0.0.30 in area 0" >> "$log_file"
    echo "$timestamp 10.0.0.21 1310: *$inner_timestamp.$millis: %OSPF-6-ADJCHANGE: Process 42 on GigabitEthernet0/0, Neighbor 10.0.3.1 (10.0.0.120): State change from DOWN to FULL" >> "$log_file"
    echo "$timestamp 10.0.0.66 1071: *$inner_timestamp.$millis: %OSPF-4-ERRRCV: Received invalid packet: mismatched area ID from backbone area from 10.0.9.1, GigabitEthernet2/0" >> "$log_file"
    echo "$timestamp 10.0.0.12 2145: *$inner_timestamp.$millis: %BGP-4-ADJCHANGE: neighbor 10.0.1.10 Up" >> "$log_file"
    echo "$timestamp 10.0.0.31 3301: *$inner_timestamp.$millis: %LINEPROTO-5-UPDOWN: Line protocol on Interface GigabitEthernet0/1, changed state to up" >> "$log_file"
    echo "$timestamp 10.0.0.33 4467: *$inner_timestamp.$millis: %ISIS-4-ADJCHANGE: Adjacency to r21 (GigabitEthernet0/0) Down, Level-1, Hold Time Expired" >> "$log_file"
    echo "$timestamp 10.0.0.32 5522: *$inner_timestamp.$millis: %SYS-5-CONFIG_I: Configured from console by admin" >> "$log_file"
    echo "$timestamp 10.0.0.12 6681: *$inner_timestamp.$millis: %ROUTING-5-UPDATE: Route 10.20.0.0/16 learned via OSPF" >> "$log_file"
    
    echo "✓ Test logs generated with IP format"
}

show_status() {
    echo "Kathara Lab Logging Status"
    echo "========================="
    echo "Date: $CURRENT_DATE"
    echo "Log Directory: $SYSLOG_DIR"
    echo ""
    
    # Check lab status
    if kathara linfo >/dev/null 2>&1; then
        echo "✓ Lab is running"
    else
        echo "⚠ Lab is not running"
    fi
    
    # Check today's log
    local today_log=$(get_log_file)
    if [ -f "$today_log" ]; then
        local lines=$(wc -l < "$today_log")
        local size=$(du -h "$today_log" | cut -f1)
        echo "✓ Today's log: $lines lines, $size"
        
        if [ "$lines" -gt 0 ]; then
            echo ""
            echo "Recent activity (last 3 lines):"
            tail -n 3 "$today_log" | sed 's/^/  /'
        fi
    else
        echo "⚠ No log file for today"
    fi
}

stop_lab() {
    echo "Stopping lab and collecting logs..."
    if kathara linfo >/dev/null 2>&1; then
        sync_logs
        kathara lclean
        echo "✓ Lab stopped, logs collected"
    else
        echo "Lab not running"
    fi
}

clean_logs() {
    local days="${1:-30}"
    echo "Removing logs older than $days days..."
    find "$SYSLOG_DIR" -name "syslog-*.log" -type f -mtime +$days -print -delete
    echo "✓ Cleanup completed"
}

mkdir -p "$SYSLOG_DIR"

case "${1:-help}" in
    "start") start_lab ;;
    "sync") sync_logs ;;
    "monitor") monitor_logs ;;
    "list") list_logs ;;
    "view") view_logs "$2" ;;
    "test") test_logs && sync_logs ;;
    "status") show_status ;;
    "stop") stop_lab ;;
    "clean") clean_logs "$2" ;;
    *) show_usage ;;
esac
