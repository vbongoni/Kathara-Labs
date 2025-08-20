#!/bin/bash
# FRR Protocol Traffic Monitor
# Real-time monitoring of FRR protocol activity

echo "=========================================="
echo "FRR Protocol Traffic Monitor"
echo "=========================================="

# Function to display menu
show_menu() {
    echo ""
    echo "Select monitoring option:"
    echo "1) Monitor OSPF activity"
    echo "2) Monitor BGP activity" 
    echo "3) Monitor RIP activity"
    echo "4) Monitor all FRR logs"
    echo "5) Show protocol status summary"
    echo "6) Monitor protocol packets with tcpdump"
    echo "7) Show routing tables"
    echo "8) Monitor interface statistics"
    echo "9) Exit"
    echo ""
    read -p "Enter your choice (1-9): " choice
}

# Function to monitor OSPF
monitor_ospf() {
    echo "=========================================="
    echo "OSPF Monitoring"
    echo "=========================================="
    echo "Press Ctrl+C to return to menu"
    echo ""
    
    # Show OSPF neighbors and database in parallel
    echo "OSPF Neighbors:"
    for router in r11 r12 r21 r31; do
        echo "--- $router ---"
        kathara exec $router -- vtysh -c "show ip ospf neighbor" 2>/dev/null || echo "OSPF not running on $router"
    done
    
    echo ""
    echo "Monitoring OSPF logs (real-time):"
    kathara exec r11 -- tail -f /var/log/frr/ospfd.log &
    kathara exec r21 -- tail -f /var/log/frr/ospfd.log &
    wait
}

# Function to monitor BGP
monitor_bgp() {
    echo "=========================================="
    echo "BGP Monitoring"
    echo "=========================================="
    echo "Press Ctrl+C to return to menu"
    echo ""
    
    # Show BGP summary
    echo "BGP Summary:"
    for router in r11 r21 r31; do
        echo "--- $router ---"
        kathara exec $router -- vtysh -c "show bgp summary" 2>/dev/null || echo "BGP not running on $router"
    done
    
    echo ""
    echo "Monitoring BGP logs (real-time):"
    kathara exec r11 -- tail -f /var/log/frr/bgpd.log &
    kathara exec r21 -- tail -f /var/log/frr/bgpd.log &
    kathara exec r31 -- tail -f /var/log/frr/bgpd.log &
    wait
}

# Function to monitor RIP
monitor_rip() {
    echo "=========================================="
    echo "RIP Monitoring"
    echo "=========================================="
    echo "Press Ctrl+C to return to menu"
    echo ""
    
    echo "RIP Status on r12:"
    kathara exec r12 -- vtysh -c "show ip rip" 2>/dev/null || echo "RIP not running on r12"
    
    echo ""
    echo "Monitoring RIP logs (real-time):"
    kathara exec r12 -- tail -f /var/log/frr/ripd.log
}

# Function to monitor all FRR logs
monitor_all_logs() {
    echo "=========================================="
    echo "All FRR Logs Monitoring"
    echo "=========================================="
    echo "Press Ctrl+C to return to menu"
    echo ""
    
    # Monitor main FRR log from all routers
    kathara exec r11 -- tail -f /var/log/frr/frr.log | sed 's/^/[R11] /' &
    kathara exec r12 -- tail -f /var/log/frr/frr.log | sed 's/^/[R12] /' &
    kathara exec r21 -- tail -f /var/log/frr/frr.log | sed 's/^/[R21] /' &
    kathara exec r31 -- tail -f /var/log/frr/frr.log | sed 's/^/[R31] /' &
    wait
}

# Function to show protocol status
show_status() {
    echo "=========================================="
    echo "Protocol Status Summary"
    echo "=========================================="
    
    echo ""
    echo "🔄 OSPF Status:"
    echo "----------------"
    for router in r11 r12 r21 r31; do
        echo "Router $router:"
        kathara exec $router -- vtysh -c "show ip ospf neighbor" 2>/dev/null | head -5 || echo "  OSPF not running"
        echo ""
    done
    
    echo "🌐 BGP Status:"
    echo "---------------"
    for router in r11 r21 r31; do
        echo "Router $router:"
        kathara exec $router -- vtysh -c "show bgp summary" 2>/dev/null | tail -5 || echo "  BGP not running"
        echo ""
    done
    
    echo "📡 RIP Status:"
    echo "---------------"
    echo "Router r12:"
    kathara exec r12 -- vtysh -c "show ip rip" 2>/dev/null || echo "  RIP not running"
    
    read -p "Press Enter to continue..."
}

# Function to monitor packets with tcpdump
monitor_packets() {
    echo "=========================================="
    echo "Protocol Packet Monitoring"
    echo "=========================================="
    echo "Press Ctrl+C to return to menu"
    echo ""
    
    echo "Select packet type to monitor:"
    echo "1) OSPF packets (protocol 89)"
    echo "2) BGP packets (port 179)"
    echo "3) RIP packets (port 520)"
    echo "4) All routing protocol packets"
    echo ""
    read -p "Enter choice (1-4): " packet_choice
    
    case $packet_choice in
        1)
            echo "Monitoring OSPF packets on r11..."
            kathara exec r11 -- tcpdump -i any -n proto 89
            ;;
        2)
            echo "Monitoring BGP packets on r21..."
            kathara exec r21 -- tcpdump -i any -n port 179
            ;;
        3)
            echo "Monitoring RIP packets on r12..."
            kathara exec r12 -- tcpdump -i any -n port 520
            ;;
        4)
            echo "Monitoring all routing protocol packets on r21..."
            kathara exec r21 -- tcpdump -i any -n '(proto 89 or port 179 or port 520)'
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
}

# Function to show routing tables
show_routing_tables() {
    echo "=========================================="
    echo "Routing Tables"
    echo "=========================================="
    
    for router in r11 r12 r21 r31; do
        echo ""
        echo "🗺️  Router $router Routing Table:"
        echo "-----------------------------------"
        kathara exec $router -- vtysh -c "show ip route" 2>/dev/null || kathara exec $router -- ip route show
        echo ""
    done
    
    read -p "Press Enter to continue..."
}

# Function to monitor interface statistics
monitor_interfaces() {
    echo "=========================================="
    echo "Interface Statistics Monitoring"
    echo "=========================================="
    echo "Press Ctrl+C to return to menu"
    echo ""
    
    # Monitor interface statistics in real-time
    watch -n 2 '
    echo "=== Interface Statistics ==="
    for router in r11 r12 r21 r31; do
        echo "Router $router:"
        kathara exec $router -- cat /proc/net/dev | grep -E "(Inter|eth)" | head -2
        kathara exec $router -- cat /proc/net/dev | grep eth | while read line; do
            echo "  $line"
        done
        echo ""
    done
    '
}

# Main loop
while true; do
    show_menu
    
    case $choice in
        1)
            monitor_ospf
            ;;
        2)
            monitor_bgp
            ;;
        3)
            monitor_rip
            ;;
        4)
            monitor_all_logs
            ;;
        5)
            show_status
            ;;
        6)
            monitor_packets
            ;;
        7)
            show_routing_tables
            ;;
        8)
            monitor_interfaces
            ;;
        9)
            echo "Exiting FRR Protocol Monitor..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please select 1-9."
            ;;
    esac
done
