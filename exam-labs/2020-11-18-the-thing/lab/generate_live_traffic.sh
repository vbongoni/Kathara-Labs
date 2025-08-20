#!/bin/bash
# save as generate_live_traffic.sh

echo "Starting comprehensive live traffic generation..."

# Function to get router IP
get_router_ip() {
    local router=$1
    local interface=${2:-eth0}
    kathara exec $router -- ip addr show $interface | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1
}

# Get router IPs
R11_IP=$(get_router_ip r11)
R12_IP=$(get_router_ip r12)
R21_IP=$(get_router_ip r21)
R31_IP=$(get_router_ip r31)

echo "Router IPs: R11=$R11_IP, R12=$R12_IP, R21=$R21_IP, R31=$R31_IP"

# Install required tools
for router in r11 r12 r21 r31; do
    echo "Installing tools on $router..."
    kathara exec $router -- apt update -qq
    kathara exec $router -- apt install -y iperf3 hping3 netcat-openbsd curl
done

# Start iperf3 servers
echo "Starting iperf3 servers..."
kathara exec r21 -- iperf3 -s -p 5001 -D
kathara exec r31 -- iperf3 -s -p 5002 -D
kathara exec r12 -- iperf3 -s -p 5003 -D

# Start netcat servers
echo "Starting netcat servers..."
kathara exec r21 -- nc -l -p 8080 &
kathara exec r31 -- nc -l -p 8081 &

# Generate continuous traffic patterns
echo "Starting traffic generation..."

# Low-bandwidth continuous traffic (r11 -> r21)
kathara exec r11 -- iperf3 -c $R21_IP -p 5001 -t 3600 -b 1M -i 30 &

# Medium-bandwidth bursts (r11 -> r31)
kathara exec r11 -- bash -c "while true; do iperf3 -c $R31_IP -p 5002 -t 10 -b 5M; sleep 60; done" &

# ICMP monitoring traffic
kathara exec r11 -- hping3 -1 -i 5 $R21_IP &  # ICMP every 5 seconds
kathara exec r12 -- hping3 -1 -i 7 $R31_IP &  # ICMP every 7 seconds

# TCP connection attempts
kathara exec r11 -- hping3 -S -p 80 -i 10 $R21_IP &  # TCP SYN every 10 seconds

# UDP probes
kathara exec r11 -- hping3 -2 -p 53 -i 15 $R31_IP &  # UDP every 15 seconds

# Application-like traffic
kathara exec r11 -- bash -c "while true; do echo 'HTTP Request from R11' | nc $R21_IP 8080; sleep 20; done" &
kathara exec r12 -- bash -c "while true; do echo 'Data from R12: $(date)' | nc $R31_IP 8081; sleep 30; done" &

# FRR Protocol Traffic Generation
echo "Configuring FRR protocols for control plane traffic..."

# Configure OSPF on all routers
echo "Setting up OSPF..."
kathara exec r11 -- vtysh -c "configure terminal" -c "router ospf" -c "ospf router-id 1.1.1.1" -c "network 0.0.0.0/0 area 0" -c "timers throttle spf 1 10 30" -c "exit" -c "exit"
kathara exec r12 -- vtysh -c "configure terminal" -c "router ospf" -c "ospf router-id 1.2.1.2" -c "network 0.0.0.0/0 area 0" -c "timers throttle spf 1 10 30" -c "exit" -c "exit"
kathara exec r21 -- vtysh -c "configure terminal" -c "router ospf" -c "ospf router-id 2.1.2.1" -c "network 0.0.0.0/0 area 0" -c "timers throttle spf 1 10 30" -c "exit" -c "exit"
kathara exec r31 -- vtysh -c "configure terminal" -c "router ospf" -c "ospf router-id 3.1.3.1" -c "network 0.0.0.0/0 area 0" -c "timers throttle spf 1 10 30" -c "exit" -c "exit"

# Configure BGP for inter-AS traffic
echo "Setting up BGP..."
kathara exec r11 -- vtysh -c "configure terminal" -c "router bgp 65001" -c "bgp router-id 1.1.1.1" -c "neighbor $R21_IP remote-as 65002" -c "neighbor $R21_IP timers 10 30" -c "exit" -c "exit"
kathara exec r21 -- vtysh -c "configure terminal" -c "router bgp 65002" -c "bgp router-id 2.1.2.1" -c "neighbor $R11_IP remote-as 65001" -c "neighbor $R11_IP timers 10 30" -c "neighbor $R31_IP remote-as 65003" -c "neighbor $R31_IP timers 10 30" -c "exit" -c "exit"
kathara exec r31 -- vtysh -c "configure terminal" -c "router bgp 65003" -c "bgp router-id 3.1.3.1" -c "neighbor $R21_IP remote-as 65002" -c "neighbor $R21_IP timers 10 30" -c "exit" -c "exit"

# Configure RIP for additional protocol diversity
echo "Setting up RIP..."
kathara exec r12 -- vtysh -c "configure terminal" -c "router rip" -c "version 2" -c "network 0.0.0.0/0" -c "timers basic 5 60 120" -c "exit" -c "exit"

# Configure static routes to generate updates
echo "Adding static routes for traffic generation..."
kathara exec r11 -- vtysh -c "configure terminal" -c "ip route 192.168.100.0/24 $R21_IP" -c "exit"
kathara exec r21 -- vtysh -c "configure terminal" -c "ip route 192.168.200.0/24 $R31_IP" -c "exit"

# Enable FRR logging to syslog
echo "Configuring FRR logging to syslog..."
for router in r11 r12 r21 r31; do
    echo "Enabling syslog on $router..."
    kathara exec $router -- vtysh -c "configure terminal" \
        -c "log syslog informational" \
        -c "log facility local7" \
        -c "log record-priority" \
        -c "log timestamp precision 6" \
        -c "exit"
done

# Configure rsyslog to capture FRR logs
echo "Configuring rsyslog for FRR..."
for router in r11 r12 r21 r31; do
    kathara exec $router -- bash -c "
        echo 'local7.*    /var/log/frr-syslog.log' >> /etc/rsyslog.conf
        echo '*.*         /var/log/all-traffic.log' >> /etc/rsyslog.conf
        service rsyslog restart
    "
done

# Generate interface events for syslog
echo "Starting interface monitoring for syslog generation..."
kathara exec r11 -- bash -c "
    while true; do
        logger -p local0.info 'R11: Interface eth0 traffic detected - $(cat /proc/net/dev | grep eth0 | awk \"{print \\\$2}\" | head -1) bytes received'
        sleep 30
    done
" &

kathara exec r21 -- bash -c "
    while true; do
        logger -p local0.info 'R21: Routing table updated - $(ip route | wc -l) routes active'
        sleep 45
    done
" &

# Generate protocol-specific syslog entries
echo "Starting protocol event logging..."
kathara exec r11 -- bash -c "
    while true; do
        logger -p local7.info 'OSPF: Hello packet sent to area 0.0.0.0'
        sleep 10
        logger -p local7.info 'BGP: Keepalive sent to neighbor $R21_IP (AS 65002)'
        sleep 20
    done
" &

kathara exec r21 -- bash -c "
    while true; do
        logger -p local7.info 'OSPF: LSA Type-1 received from router 1.1.1.1'
        sleep 15
        logger -p local7.info 'BGP: Update received from neighbor $R11_IP'
        sleep 25
    done
" &

kathara exec r31 -- bash -c "
    while true; do
        logger -p local7.info 'OSPF: SPF calculation completed in 12ms'
        sleep 20
        logger -p local7.info 'BGP: Route 172.16.3.0/24 announced to peer $R21_IP'
        sleep 35
    done
" &

kathara exec r12 -- bash -c "
    while true; do
        logger -p local7.info 'RIP: Route update sent - 3 networks advertised'
        sleep 5
        logger -p local0.info 'Interface: Bandwidth utilization on eth0: 75%'
        sleep 60
    done
" &

echo "Live traffic generation started!"
echo "Traffic patterns active:"
echo "- iperf3: Continuous 1Mbps stream (r11->r21)"
echo "- iperf3: 5Mbps bursts every minute (r11->r31)"
echo "- ICMP: Ping every 5s (r11->r21), every 7s (r12->r31)"
echo "- TCP: SYN probes every 10s (r11->r21)"
echo "- UDP: Probes every 15s (r11->r31)"
echo "- HTTP-like: Requests every 20s (r11->r21), every 30s (r12->r31)"
echo "- OSPF: Hello packets, LSA updates, SPF calculations"
echo "- BGP: Keepalives, route updates between AS 65001, 65002, 65003"
echo "- RIP: Route advertisements every 5 seconds on r12"
echo "- SYSLOG: Protocol events logged every 5-60 seconds"
echo "- SYSLOG: Interface monitoring and traffic statistics"
echo "- Syslog: FRR logging to /var/log/frr-syslog.log"
echo "- Syslog: All traffic logging to /var/log/all-traffic.log"

echo ""
echo "To monitor live syslog activity:"
echo "kathara exec r11 -- tail -f /var/log/syslog"
echo "kathara exec r11 -- tail -f /var/log/frr-syslog.log"
echo "kathara exec r11 -- tail -f /var/log/all-traffic.log"
echo ""
echo "To stop traffic generation, run:"
echo "kathara exec r11 -- pkill -f 'iperf3\\|hping3\\|nc\\|logger'"
echo "kathara exec r12 -- pkill -f 'iperf3\\|hping3\\|nc\\|logger'"
echo "kathara exec r21 -- pkill -f 'logger'"
echo "kathara exec r31 -- pkill -f 'logger'"
echo ""
echo "To stop FRR protocols:"
echo "for router in r11 r12 r21 r31; do"
echo "  kathara exec \$router -- vtysh -c 'configure terminal' -c 'no router ospf' -c 'no router bgp' -c 'no router rip' -c 'exit'"
echo "done"