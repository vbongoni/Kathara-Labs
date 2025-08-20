#!/bin/bash

# Enhanced demonstration script for Cisco-style syslog format
echo "======================================================================"
echo "    Kathara Lab - Enhanced Cisco-Style Syslog Format Demo"
echo "======================================================================"
echo ""

echo "Generating realistic network events with Cisco-style formatting..."
echo ""

# Generate various Cisco-style events across devices
echo "1. Generating BGP events..."
kathara exec r11 -- log_network_event bgp "neighbor 10.166.156.198 Down"
kathara exec r21 -- log_network_event bgp "Maximum number of prefixes reached from 10.166.156.198: 1726/8328"

echo "2. Generating OSPF events..."
kathara exec r11 -- log_network_event ospf "Process 44, SPF calculation completed for area 1, took 356 ms"
kathara exec r31 -- log_network_event ospf "Process 1, Nbr 10.0.0.5 on FastEthernet0/1 from LOADING to FULL"

echo "3. Generating ISIS events..."
kathara exec r12 -- log_network_event isis "Level-1 LSP 5793.7867.7981-00 with a sequence number skip detected from 1587.3240.6143 on GigabitEthernet0/0"
kathara exec b012 -- log_network_event isis "IS-IS authentication failed on interface GigabitEthernet0/0, packet from 8964.6628.2637"

echo "4. Generating interface events..."
kathara exec r11 -- log_network_event interface "GigabitEthernet0/1, changed state to down"
kathara exec r21 -- log_network_event interface "FastEthernet0/0, changed state to up"

echo "5. Generating routing events..."
kathara exec r31 -- log_network_event routing "Route 192.168.1.0/24 installed via OSPF"
kathara exec b02 -- log_network_event routing "Static route 10.0.0.0/8 removed from routing table"

echo ""
echo "======================================================================"
echo "                     Sample Cisco-Style Log Output"
echo "======================================================================"
echo ""

echo "--- r11 Latest Events ---"
kathara exec r11 -- tail -8 /var/log/syslog

echo ""
echo "--- r21 Latest Events ---"
kathara exec r21 -- tail -4 /var/log/syslog

echo ""
echo "--- BGP Specialized Log (r11) ---"
kathara exec r11 -- cat /var/log/bgp.log 2>/dev/null | tail -3 || echo "No BGP log file found"

echo ""
echo "--- ISIS Specialized Log (r12) ---"
kathara exec r12 -- cat /var/log/isis.log 2>/dev/null | tail -2 || echo "No ISIS log file found"

echo ""
echo "======================================================================"
echo "                      Format Analysis"
echo "======================================================================"
echo ""
echo "Cisco-style format implemented:"
echo "  Format: MMM DD HH:MM:SS IP_ADDRESS PID: *MMM DD HH:MM:SS HH:MM:SS.mmm: MESSAGE"
echo ""
echo "Key features:"
echo "  ✓ Standard syslog timestamp (MMM DD HH:MM:SS)"
echo "  ✓ Device IP address instead of hostname"
echo "  ✓ Simulated process ID (random per session/tag)"
echo "  ✓ Cisco-style internal timestamp with milliseconds"
echo "  ✓ Protocol-specific severity levels (%BGP-4, %OSPF-6, etc.)"
echo "  ✓ Realistic network event messages"
echo "  ✓ Specialized log file routing maintained"
echo ""
echo "Example formats match the provided templates:"
echo "  BGP: %BGP-4-ADJCHANGE, %BGP-4-MAXPFX"
echo "  OSPF: OSPF-6-ADJCHG, OSPF-6-SPFEND"
echo "  ISIS: %ISIS-4-ADJCHANGE, %ISIS-4-SEQNUMSKIP, %ISIS-3-AUTHFAIL"
echo "  Interface: %LINEPROTO-5-UPDOWN"
echo "======================================================================"
