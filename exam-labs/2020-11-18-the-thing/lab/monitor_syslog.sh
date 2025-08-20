#!/bin/bash
# Live Syslog Monitor for Kathara Lab
# Monitor real-time syslog activity from network traffic

echo "=========================================="
echo "Live Syslog Traffic Monitor"
echo "=========================================="

# Function to display menu
show_menu() {
    echo ""
    echo "Select monitoring option:"
    echo "1) Monitor all syslog activity (real-time)"
    echo "2) Monitor FRR protocol logs only"
    echo "3) Monitor interface and traffic logs"
    echo "4) Monitor specific router syslog"
    echo "5) Show syslog statistics"
    echo "6) Search syslog for specific events"
    echo "7) Monitor syslog with timestamps"
    echo "8) Export syslog to file"
    echo "9) Exit"
    echo ""
    read -p "Enter your choice (1-9): " choice
}

# Function to monitor all syslog activity
monitor_all_syslog() {
    echo "=========================================="
    echo "All Syslog Activity (Real-time)"
    echo "=========================================="
    echo "Press Ctrl+C to return to menu"
    echo ""
    
    # Monitor syslog from all routers with router labels
    kathara exec r11 -- tail -f /var/log/syslog | sed 's/^/[R11] /' &
    kathara exec r12 -- tail -f /var/log/syslog | sed 's/^/[R12] /' &
    kathara exec r21 -- tail -f /var/log/syslog | sed 's/^/[R21] /' &
    kathara exec r31 -- tail -f /var/log/syslog | sed 's/^/[R31] /' &
    
    # Also monitor the consolidated traffic log if it exists
    kathara exec r11 -- tail -f /var/log/all-traffic.log 2>/dev/null | sed 's/^/[ALL] /' &
    
    wait
}

# Function to monitor FRR protocol logs
monitor_frr_logs() {
    echo "=========================================="
    echo "FRR Protocol Logs (Real-time)"
    echo "=========================================="
    echo "Press Ctrl+C to return to menu"
    echo ""
    
    # Monitor FRR-specific syslog entries
    kathara exec r11 -- tail -f /var/log/frr-syslog.log 2>/dev/null | sed 's/^/[R11-FRR] /' &
    kathara exec r12 -- tail -f /var/log/frr-syslog.log 2>/dev/null | sed 's/^/[R12-FRR] /' &
    kathara exec r21 -- tail -f /var/log/frr-syslog.log 2>/dev/null | sed 's/^/[R21-FRR] /' &
    kathara exec r31 -- tail -f /var/log/frr-syslog.log 2>/dev/null | sed 's/^/[R31-FRR] /' &
    
    # Also monitor direct FRR logs
    kathara exec r11 -- tail -f /var/log/frr/frr.log 2>/dev/null | sed 's/^/[R11-FRR-Direct] /' &
    kathara exec r21 -- tail -f /var/log/frr/frr.log 2>/dev/null | sed 's/^/[R21-FRR-Direct] /' &
    
    wait
}

# Function to monitor interface and traffic logs
monitor_interface_logs() {
    echo "=========================================="
    echo "Interface and Traffic Logs (Real-time)"
    echo "=========================================="
    echo "Press Ctrl+C to return to menu"
    echo ""
    
    # Filter syslog for interface and traffic-related entries
    kathara exec r11 -- tail -f /var/log/syslog | grep -E "(Interface|traffic|eth|bandwidth)" | sed 's/^/[R11-IF] /' &
    kathara exec r12 -- tail -f /var/log/syslog | grep -E "(Interface|traffic|eth|bandwidth)" | sed 's/^/[R12-IF] /' &
    kathara exec r21 -- tail -f /var/log/syslog | grep -E "(Interface|traffic|eth|Routing)" | sed 's/^/[R21-IF] /' &
    kathara exec r31 -- tail -f /var/log/syslog | grep -E "(Interface|traffic|eth|bandwidth)" | sed 's/^/[R31-IF] /' &
    
    wait
}

# Function to monitor specific router
monitor_specific_router() {
    echo "Select router to monitor:"
    echo "1) r11"
    echo "2) r12" 
    echo "3) r21"
    echo "4) r31"
    echo ""
    read -p "Enter choice (1-4): " router_choice
    
    case $router_choice in
        1) ROUTER="r11" ;;
        2) ROUTER="r12" ;;
        3) ROUTER="r21" ;;
        4) ROUTER="r31" ;;
        *) echo "Invalid choice"; return ;;
    esac
    
    echo "=========================================="
    echo "Monitoring $ROUTER Syslog (Real-time)"
    echo "=========================================="
    echo "Press Ctrl+C to return to menu"
    echo ""
    
    kathara exec $ROUTER -- tail -f /var/log/syslog
}

# Function to show syslog statistics
show_syslog_stats() {
    echo "=========================================="
    echo "Syslog Statistics"
    echo "=========================================="
    
    for router in r11 r12 r21 r31; do
        echo ""
        echo "📊 Router $router Statistics:"
        echo "----------------------------"
        
        # Count total syslog entries
        TOTAL=$(kathara exec $router -- wc -l /var/log/syslog 2>/dev/null | awk '{print $1}' || echo "0")
        echo "Total syslog entries: $TOTAL"
        
        # Count FRR entries
        FRR_COUNT=$(kathara exec $router -- grep -c "OSPF\\|BGP\\|RIP\\|frr" /var/log/syslog 2>/dev/null || echo "0")
        echo "FRR protocol entries: $FRR_COUNT"
        
        # Count interface entries
        IF_COUNT=$(kathara exec $router -- grep -c "Interface\\|eth\\|bandwidth" /var/log/syslog 2>/dev/null || echo "0")
        echo "Interface/traffic entries: $IF_COUNT"
        
        # Show last 3 entries
        echo "Recent entries:"
        kathara exec $router -- tail -3 /var/log/syslog 2>/dev/null | sed 's/^/  /' || echo "  No entries found"
    done
    
    read -p "Press Enter to continue..."
}

# Function to search syslog
search_syslog() {
    echo "Enter search term (e.g., OSPF, BGP, Interface, traffic):"
    read -p "Search: " search_term
    
    if [ -z "$search_term" ]; then
        echo "No search term provided"
        return
    fi
    
    echo "=========================================="
    echo "Searching for: $search_term"
    echo "=========================================="
    
    for router in r11 r12 r21 r31; do
        echo ""
        echo "🔍 Results from $router:"
        echo "-------------------------"
        kathara exec $router -- grep -i "$search_term" /var/log/syslog 2>/dev/null | tail -5 | sed 's/^/  /' || echo "  No matches found"
    done
    
    read -p "Press Enter to continue..."
}

# Function to monitor with timestamps
monitor_with_timestamps() {
    echo "=========================================="
    echo "Syslog with Detailed Timestamps"
    echo "=========================================="
    echo "Press Ctrl+C to return to menu"
    echo ""
    
    # Monitor with detailed timestamps and router info
    while true; do
        for router in r11 r12 r21 r31; do
            TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
            LATEST=$(kathara exec $router -- tail -1 /var/log/syslog 2>/dev/null || echo "No log")
            if [ "$LATEST" != "No log" ] && [ -n "$LATEST" ]; then
                echo "[$TIMESTAMP] [$router] $LATEST"
            fi
        done
        sleep 2
    done
}

# Function to export syslog
export_syslog() {
    echo "=========================================="
    echo "Export Syslog to File"
    echo "=========================================="
    
    EXPORT_DIR="./syslog_export_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$EXPORT_DIR"
    
    echo "Exporting syslog files to: $EXPORT_DIR"
    
    for router in r11 r12 r21 r31; do
        echo "Exporting $router syslog..."
        kathara exec $router -- cp /var/log/syslog "$EXPORT_DIR/${router}_syslog.log" 2>/dev/null || echo "No syslog for $router"
        kathara exec $router -- cp /var/log/frr-syslog.log "$EXPORT_DIR/${router}_frr.log" 2>/dev/null || echo "No FRR log for $router"
        kathara exec $router -- cp /var/log/all-traffic.log "$EXPORT_DIR/${router}_traffic.log" 2>/dev/null || echo "No traffic log for $router"
    done
    
    # Create summary file
    echo "Creating summary..."
    cat > "$EXPORT_DIR/summary.txt" << EOF
Syslog Export Summary
Generated: $(date)
Lab: Kathara FRR Traffic Generation

Exported Files:
$(ls -la "$EXPORT_DIR")

Total Entries by Router:
EOF
    
    for router in r11 r12 r21 r31; do
        if [ -f "$EXPORT_DIR/${router}_syslog.log" ]; then
            COUNT=$(wc -l "$EXPORT_DIR/${router}_syslog.log" | awk '{print $1}')
            echo "$router: $COUNT entries" >> "$EXPORT_DIR/summary.txt"
        fi
    done
    
    echo "Export completed to: $EXPORT_DIR"
    echo "Summary file: $EXPORT_DIR/summary.txt"
    
    read -p "Press Enter to continue..."
}

# Function to test syslog generation
test_syslog_generation() {
    echo "=========================================="
    echo "Testing Syslog Generation"
    echo "=========================================="
    
    echo "Generating test syslog entries..."
    
    # Generate test entries on each router
    for router in r11 r12 r21 r31; do
        kathara exec $router -- logger -p local0.info "TEST: Syslog generation test from $router at $(date)"
        kathara exec $router -- logger -p local7.info "TEST: FRR protocol test from $router"
    done
    
    echo "Test entries generated. Check syslog in 2 seconds..."
    sleep 2
    
    echo ""
    echo "Recent test entries:"
    for router in r11 r12 r21 r31; do
        echo "--- $router ---"
        kathara exec $router -- tail -2 /var/log/syslog | grep "TEST:" | sed 's/^/  /'
    done
    
    read -p "Press Enter to continue..."
}

# Main loop
while true; do
    show_menu
    
    case $choice in
        1)
            monitor_all_syslog
            ;;
        2)
            monitor_frr_logs
            ;;
        3)
            monitor_interface_logs
            ;;
        4)
            monitor_specific_router
            ;;
        5)
            show_syslog_stats
            ;;
        6)
            search_syslog
            ;;
        7)
            monitor_with_timestamps
            ;;
        8)
            export_syslog
            ;;
        9)
            echo "Exiting Live Syslog Monitor..."
            exit 0
            ;;
        t|test)
            test_syslog_generation
            ;;
        *)
            echo "Invalid choice. Please select 1-9 (or 'test' for syslog test)."
            ;;
    esac
done
