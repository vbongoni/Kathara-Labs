#!/bin/bash
# FRR Protocol Traffic Generation Script
# Generates authentic routing protocol traffic for Kathara lab

echo "=========================================="
echo "FRR Protocol Traffic Generator"
echo "=========================================="

# Function to get router IP
get_router_ip() {
    local router=$1
    local interface=${2:-eth0}
    kathara exec $router -- ip addr show $interface | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1
}

# Function to wait for FRR to be ready
wait_for_frr() {
    local router=$1
    echo "Waiting for FRR to be ready on $router..."
    for i in {1..30}; do
        if kathara exec $router -- vtysh -c "show version" >/dev/null 2>&1; then
            echo "FRR ready on $router"
            return 0
        fi
        sleep 2
    done
    echo "Warning: FRR may not be fully ready on $router"
    return 1
}

# Get router IPs
echo "Discovering router IP addresses..."
R11_IP=$(get_router_ip r11)
R12_IP=$(get_router_ip r12)
R21_IP=$(get_router_ip r21)
R31_IP=$(get_router_ip r31)

echo "Router IPs detected:"
echo "  R11: $R11_IP"
echo "  R12: $R12_IP"
echo "  R21: $R21_IP"
echo "  R31: $R31_IP"

# Wait for FRR to be ready on all routers
echo ""
echo "Checking FRR readiness..."
for router in r11 r12 r21 r31; do
    wait_for_frr $router
done

echo ""
echo "=========================================="
echo "Configuring OSPF Protocol"
echo "=========================================="

# Configure OSPF on all routers with different timers for more traffic
kathara exec r11 -- vtysh -c "configure terminal" \
    -c "router ospf" \
    -c "ospf router-id 1.1.1.1" \
    -c "network 0.0.0.0/0 area 0" \
    -c "timers throttle spf 1 5 10" \
    -c "timers lsa arrival 100" \
    -c "area 0 hello-interval 5" \
    -c "area 0 dead-interval 15" \
    -c "exit" \
    -c "exit"

kathara exec r12 -- vtysh -c "configure terminal" \
    -c "router ospf" \
    -c "ospf router-id 1.2.1.2" \
    -c "network 0.0.0.0/0 area 0" \
    -c "timers throttle spf 1 5 10" \
    -c "timers lsa arrival 100" \
    -c "area 0 hello-interval 5" \
    -c "area 0 dead-interval 15" \
    -c "exit" \
    -c "exit"

kathara exec r21 -- vtysh -c "configure terminal" \
    -c "router ospf" \
    -c "ospf router-id 2.1.2.1" \
    -c "network 0.0.0.0/0 area 0" \
    -c "timers throttle spf 1 5 10" \
    -c "timers lsa arrival 100" \
    -c "area 0 hello-interval 5" \
    -c "area 0 dead-interval 15" \
    -c "exit" \
    -c "exit"

kathara exec r31 -- vtysh -c "configure terminal" \
    -c "router ospf" \
    -c "ospf router-id 3.1.3.1" \
    -c "network 0.0.0.0/0 area 0" \
    -c "timers throttle spf 1 5 10" \
    -c "timers lsa arrival 100" \
    -c "area 0 hello-interval 5" \
    -c "area 0 dead-interval 15" \
    -c "exit" \
    -c "exit"

echo "OSPF configured with aggressive timers (Hello: 5s, Dead: 15s)"

echo ""
echo "=========================================="
echo "Configuring BGP Protocol"
echo "=========================================="

# Configure BGP with frequent keepalives and updates
kathara exec r11 -- vtysh -c "configure terminal" \
    -c "router bgp 65001" \
    -c "bgp router-id 1.1.1.1" \
    -c "bgp log-neighbor-changes" \
    -c "neighbor $R21_IP remote-as 65002" \
    -c "neighbor $R21_IP timers 10 30" \
    -c "neighbor $R21_IP timers connect 5" \
    -c "address-family ipv4 unicast" \
    -c "network 10.1.0.0/24" \
    -c "network 172.16.1.0/24" \
    -c "exit-address-family" \
    -c "exit" \
    -c "exit"

kathara exec r21 -- vtysh -c "configure terminal" \
    -c "router bgp 65002" \
    -c "bgp router-id 2.1.2.1" \
    -c "bgp log-neighbor-changes" \
    -c "neighbor $R11_IP remote-as 65001" \
    -c "neighbor $R11_IP timers 10 30" \
    -c "neighbor $R11_IP timers connect 5" \
    -c "neighbor $R31_IP remote-as 65003" \
    -c "neighbor $R31_IP timers 10 30" \
    -c "neighbor $R31_IP timers connect 5" \
    -c "address-family ipv4 unicast" \
    -c "network 10.2.0.0/24" \
    -c "network 172.16.2.0/24" \
    -c "exit-address-family" \
    -c "exit" \
    -c "exit"

kathara exec r31 -- vtysh -c "configure terminal" \
    -c "router bgp 65003" \
    -c "bgp router-id 3.1.3.1" \
    -c "bgp log-neighbor-changes" \
    -c "neighbor $R21_IP remote-as 65002" \
    -c "neighbor $R21_IP timers 10 30" \
    -c "neighbor $R21_IP timers connect 5" \
    -c "address-family ipv4 unicast" \
    -c "network 10.3.0.0/24" \
    -c "network 172.16.3.0/24" \
    -c "exit-address-family" \
    -c "exit" \
    -c "exit"

echo "BGP configured with fast timers (Keepalive: 10s, Hold: 30s)"

echo ""
echo "=========================================="
echo "Configuring RIP Protocol"
echo "=========================================="

# Configure RIP on r12 for additional protocol diversity
kathara exec r12 -- vtysh -c "configure terminal" \
    -c "router rip" \
    -c "version 2" \
    -c "network 0.0.0.0/0" \
    -c "timers basic 5 30 60" \
    -c "redistribute static" \
    -c "redistribute connected" \
    -c "exit" \
    -c "exit"

echo "RIP configured with 5-second update intervals"

echo ""
echo "=========================================="
echo "Adding Dynamic Route Changes"
echo "=========================================="

# Function to create dynamic route changes
create_route_flapping() {
    echo "Starting route flapping simulation..."
    
    # Route flapping on r11 - add/remove routes every 60 seconds
    kathara exec r11 -- bash -c "
        while true; do
            vtysh -c 'configure terminal' -c 'ip route 192.168.100.0/24 $R21_IP' -c 'exit'
            sleep 30
            vtysh -c 'configure terminal' -c 'no ip route 192.168.100.0/24 $R21_IP' -c 'exit'
            sleep 30
        done
    " &
    
    # Interface flapping on r21 - bring interface up/down periodically
    kathara exec r21 -- bash -c "
        while true; do
            sleep 90
            ip link set eth1 down
            sleep 10
            ip link set eth1 up
            sleep 90
        done
    " &
    
    # Metric changes on r31 to trigger OSPF updates
    kathara exec r31 -- bash -c "
        while true; do
            vtysh -c 'configure terminal' -c 'interface eth0' -c 'ip ospf cost 100' -c 'exit' -c 'exit'
            sleep 45
            vtysh -c 'configure terminal' -c 'interface eth0' -c 'ip ospf cost 1' -c 'exit' -c 'exit'
            sleep 45
        done
    " &
}

# Start dynamic changes
create_route_flapping

echo ""
echo "=========================================="
echo "Protocol Traffic Generation Active"
echo "=========================================="

echo "Active FRR protocols generating traffic:"
echo ""
echo "🔄 OSPF (Open Shortest Path First):"
echo "   - Hello packets every 5 seconds"
echo "   - LSA flooding and SPF calculations"
echo "   - Router IDs: r11(1.1.1.1), r12(1.2.1.2), r21(2.1.2.1), r31(3.1.3.1)"
echo ""
echo "🌐 BGP (Border Gateway Protocol):"
echo "   - Keepalives every 10 seconds"
echo "   - Route advertisements between AS 65001, 65002, 65003"
echo "   - Network announcements: 10.x.0.0/24, 172.16.x.0/24"
echo ""
echo "📡 RIP (Routing Information Protocol):"
echo "   - Route updates every 5 seconds from r12"
echo "   - Redistributing static and connected routes"
echo ""
echo "⚡ Dynamic Events:"
echo "   - Route flapping on r11 (192.168.100.0/24 every 60s)"
echo "   - Interface flapping on r21 (eth1 every 3 minutes)"
echo "   - OSPF cost changes on r31 (every 90s)"

echo ""
echo "=========================================="
echo "Monitoring Commands"
echo "=========================================="

echo "To monitor FRR protocol activity:"
echo ""
echo "📊 OSPF Status:"
echo "   kathara exec r11 -- vtysh -c 'show ip ospf neighbor'"
echo "   kathara exec r11 -- vtysh -c 'show ip ospf database'"
echo ""
echo "🔗 BGP Status:"
echo "   kathara exec r11 -- vtysh -c 'show bgp summary'"
echo "   kathara exec r21 -- vtysh -c 'show bgp neighbors'"
echo ""
echo "📋 RIP Status:"
echo "   kathara exec r12 -- vtysh -c 'show ip rip'"
echo ""
echo "📝 Live Protocol Logs:"
echo "   kathara exec r11 -- tail -f /var/log/frr/frr.log"
echo "   kathara exec r21 -- tail -f /var/log/frr/bgpd.log"
echo "   kathara exec r31 -- tail -f /var/log/frr/ospfd.log"

echo ""
echo "=========================================="
echo "Cleanup Commands"
echo "=========================================="

echo "To stop FRR protocol traffic generation:"
echo ""
echo "🛑 Stop all routing protocols:"
echo "for router in r11 r12 r21 r31; do"
echo "  kathara exec \$router -- vtysh -c 'configure terminal' -c 'no router ospf' -c 'no router bgp' -c 'no router rip' -c 'exit'"
echo "done"
echo ""
echo "🔄 Stop dynamic route changes:"
echo "for router in r11 r21 r31; do"
echo "  kathara exec \$router -- pkill -f 'vtysh\\|bash'"
echo "done"

echo ""
echo "FRR Protocol Traffic Generation is now ACTIVE! 🚀"
echo "Monitor your network logs to see the live protocol activity."
