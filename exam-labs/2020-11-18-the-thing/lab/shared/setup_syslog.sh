#!/bin/bash

# Shared Syslog Setup Script for Kathara Lab
# This script enables real syslog functionality in FRR containers

# Prevent multiple runs
if [ -f /tmp/syslog_setup_done ]; then
    echo "Syslog already configured on $(hostname)"
    exit 0
fi

echo "Setting up syslog for device: $(hostname)"

# Function to install and configure rsyslog
setup_syslog() {
    # Update package lists and install rsyslog
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq > /dev/null 2>&1
    
    # Try to install rsyslog
    if apt-get install -y rsyslog > /dev/null 2>&1; then
        echo "Successfully installed rsyslog"
        
        # Create rsyslog configuration
        cat > /etc/rsyslog.conf << 'EOF'
# Enhanced rsyslog configuration for network simulation
$ModLoad imuxsock
$ModLoad imklog

# Global directives
$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat
$RepeatedMsgReduction on

# Include additional configuration files
$IncludeConfig /etc/rsyslog.d/*.conf

# Log network simulation events
:programname, isequal, "NetworkSim" /var/log/network-sim.log
:programname, isequal, "FRR" /var/log/frr.log
:programname, isequal, "BGP" /var/log/bgp.log
:programname, isequal, "OSPF" /var/log/ospf.log

# Standard log files
kern.*                          /var/log/kern.log
*.info;mail.none;authpriv.none;cron.none /var/log/messages
authpriv.*                      /var/log/auth.log
mail.*                          /var/log/mail.log
cron.*                          /var/log/cron.log
daemon.*                        /var/log/daemon.log
*.emerg                         *

# Network device specific logs
local0.*                        /var/log/network.log
local1.*                        /var/log/routing.log
local2.*                        /var/log/interfaces.log

# All logs also go to main syslog
*.*                             /var/log/syslog
EOF

        # Create directory for additional configs
        mkdir -p /etc/rsyslog.d
        
        # Create network-specific logging config
        cat > /etc/rsyslog.d/50-network.conf << 'EOF'
# Network simulation specific logging rules

# FRR daemon logs
if $programname startswith 'bgpd' then /var/log/frr-bgp.log
if $programname startswith 'ospfd' then /var/log/frr-ospf.log
if $programname startswith 'zebra' then /var/log/frr-zebra.log
if $programname startswith 'isisd' then /var/log/frr-isis.log

# Interface and network events
if $msg contains 'link' then /var/log/interface-events.log
if $msg contains 'route' then /var/log/routing-events.log
if $msg contains 'neighbor' then /var/log/neighbor-events.log
EOF

        # Start rsyslog
        mkdir -p /run/rsyslog
        service rsyslog start || rsyslogd
        
        # Test rsyslog
        logger -t "NetworkSim" "Syslog initialized for $(hostname) at $(date)"
        logger -p local0.info -t "NetworkSim" "Network logging ready"
        
    else
        echo "Failed to install rsyslog, using fallback logging method"
        
        # Create syslog files manually
        touch /var/log/syslog
        touch /var/log/messages  
        touch /var/log/kern.log
        touch /var/log/auth.log
        touch /var/log/daemon.log
        
        # Create logging function
        cat > /usr/local/bin/net_logger << 'EOF'
#!/bin/bash
# Network logging function with Cisco-style format

case "$1" in
    "-t")
        tag="$2"
        shift 2
        message="$*"
        ;;
    "-p")
        priority="$2"
        shift 2
        if [ "$1" = "-t" ]; then
            tag="$2"
            shift 2
        else
            tag="system"
        fi
        message="$*"
        ;;
    *)
        tag="system"
        message="$*"
        ;;
esac

# Get interface IP address (prefer eth0, fallback to first available)
ip_addr=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' 2>/dev/null)
if [ -z "$ip_addr" ]; then
    ip_addr=$(hostname -I | awk '{print $1}' 2>/dev/null)
fi
if [ -z "$ip_addr" ]; then
    ip_addr="127.0.0.1"
fi

# Generate process ID (simulate different process IDs for different tags)
case "$tag" in
    "BGP"|"bgp") pid=$((RANDOM % 9000 + 1000)) ;;
    "OSPF"|"ospf") pid=$((RANDOM % 9000 + 1000)) ;;
    "ISIS"|"isis") pid=$((RANDOM % 9000 + 1000)) ;;
    "INTERFACE"|"interface") pid=$((RANDOM % 9000 + 1000)) ;;
    "ROUTING"|"routing") pid=$((RANDOM % 9000 + 1000)) ;;
    *) pid=$((RANDOM % 9000 + 1000)) ;;
esac

# Cisco-style timestamp format
timestamp1=$(date '+%b %d %H:%M:%S')
timestamp2=$(date '+%H:%M:%S.%3N')

# Format message in Cisco style
cisco_msg="*${timestamp1} ${timestamp2}: ${message}"

# Full syslog entry format: timestamp ip_address pid: cisco_message
formatted_msg="$timestamp1 $ip_addr $pid: $cisco_msg"

# Log to multiple files
echo "$formatted_msg" >> /var/log/syslog
echo "$formatted_msg" >> /var/log/messages

# Route based on tag
case "$tag" in
    "NetworkSim"|"FRR"|"BGP"|"OSPF"|"ISIS"|"INTERFACE"|"ROUTING")
        echo "$formatted_msg" >> "/var/log/$(echo $tag | tr '[:upper:]' '[:lower:]').log"
        ;;
esac

# Also use system logger if available (but not the overridden one)
if command -v /bin/logger >/dev/null 2>&1; then
    /bin/logger -t "$tag" "$message" 2>/dev/null || true
fi
EOF
        chmod +x /usr/local/bin/net_logger
        
        # Create a fallback logger that doesn't override system logger
        # Test the logger
        /usr/local/bin/net_logger -t "NetworkSim" "Manual logging initialized for $(hostname)"
    fi
}

# Create log directories
mkdir -p /var/log

# Setup syslog
setup_syslog

# Create convenience logging functions for network simulation
cat > /usr/local/bin/log_network_event << 'EOF'
#!/bin/bash
# Convenience function for logging network events in Cisco-style format

event_type="$1"
shift
message="$*"

case "$event_type" in
    "interface")
        # Format as interface event with severity
        cisco_msg="%LINEPROTO-5-UPDOWN: Line protocol on Interface ${message}"
        /usr/local/bin/net_logger -t "INTERFACE" "$cisco_msg"
        ;;
    "routing")
        # Format as routing event
        cisco_msg="%ROUTING-5-UPDATE: ${message}"
        /usr/local/bin/net_logger -t "ROUTING" "$cisco_msg"
        ;;
    "bgp")
        # Format as BGP event with severity
        cisco_msg="%BGP-4-ADJCHANGE: ${message}"
        /usr/local/bin/net_logger -t "BGP" "$cisco_msg"
        ;;
    "ospf")
        # Format as OSPF event
        cisco_msg="OSPF-6-ADJCHG: ${message}"
        /usr/local/bin/net_logger -t "OSPF" "$cisco_msg"
        ;;
    "isis")
        # Format as ISIS event
        cisco_msg="%ISIS-4-ADJCHANGE: ${message}"
        /usr/local/bin/net_logger -t "ISIS" "$cisco_msg"
        ;;
    "system")
        # Format as system event
        cisco_msg="%SYS-5-CONFIG_I: ${message}"
        /usr/local/bin/net_logger -t "NetworkSim" "$cisco_msg"
        ;;
    *)
        # Default format
        cisco_msg="%SYS-6-LOGGINGHOST_STARTSTOP: ${event_type}: ${message}"
        /usr/local/bin/net_logger -t "NetworkSim" "$cisco_msg"
        ;;
esac
EOF
chmod +x /usr/local/bin/log_network_event

# Log the completion
if command -v log_network_event >/dev/null 2>&1; then
    log_network_event "system" "Syslog setup completed for $(hostname)"
else
    /usr/local/bin/net_logger -t "NetworkSim" "Syslog setup completed for $(hostname)" 2>/dev/null || echo "Syslog setup completed for $(hostname)" >> /var/log/syslog
fi

# Mark setup as complete
touch /tmp/syslog_setup_done

echo "Syslog setup completed for $(hostname)"
