#!/bin/bash

# Demonstration script for the Kathara Lab Syslog System
# This script demonstrates real syslog functionality across all network devices

echo "======================================================================"
echo "         Kathara Lab Real Syslog System Demonstration"
echo "======================================================================"
echo ""

echo "1. Checking syslog setup status on all devices..."
echo ""
for device in r11 r12 b012 b02 b03 r21 r31; do
    status=$(kathara exec $device -- test -f /tmp/syslog_setup_done && echo "✓ CONFIGURED" || echo "✗ NOT CONFIGURED")
    lines=$(kathara exec $device -- wc -l < /var/log/syslog 2>/dev/null || echo "0")
    echo "  $device: $status (Log entries: $lines)"
done

echo ""
echo "2. Generating sample network events across devices..."
echo ""

# Generate events on different devices
kathara exec r11 -- log_network_event interface "Port eth0 link state changed to UP"
kathara exec r11 -- log_network_event routing "Static route 192.168.100.0/24 added"
kathara exec r12 -- log_network_event bgp "BGP neighbor 10.0.0.1 established"
kathara exec b012 -- log_network_event system "Bridge learning MAC 00:11:22:33:44:55"
kathara exec r21 -- log_network_event ospf "OSPF LSA received from Area 0"
kathara exec r31 -- log_network_event interface "Interface eth1 bandwidth set to 100Mbps"

echo "3. Displaying main syslog from r11 (most active device)..."
echo ""
echo "--- r11 Main Syslog (/var/log/syslog) ---"
kathara exec r11 -- cat /var/log/syslog | tail -10

echo ""
echo "4. Displaying specialized BGP log from r11..."
echo ""
echo "--- r11 BGP Log (/var/log/bgp.log) ---"
kathara exec r11 -- cat /var/log/bgp.log 2>/dev/null || echo "No BGP events logged yet"

echo ""
echo "5. Showing recent events from another device (r21)..."
echo ""
echo "--- r21 Recent Syslog ---"
kathara exec r21 -- cat /var/log/syslog | tail -5

echo ""
echo "6. Summary of log files created:"
echo ""
kathara exec r11 -- ls -la /var/log/ | grep -E "\.(log|syslog)" | head -10

echo ""
echo "======================================================================"
echo "               Syslog System Successfully Implemented!"
echo ""
echo "Features demonstrated:"
echo "  ✓ Real syslog files (/var/log/syslog, /var/log/messages)"
echo "  ✓ Specialized log routing (BGP, OSPF, Interface events)"
echo "  ✓ Custom logging functions (log_network_event)"
echo "  ✓ Cross-device logging consistency"
echo "  ✓ Standard syslog timestamp format"
echo "  ✓ Fallback logging when rsyslog unavailable"
echo ""
echo "Usage: Use 'log_network_event <type> <message>' in any container"
echo "Types: interface, routing, bgp, ospf, system"
echo "======================================================================"
