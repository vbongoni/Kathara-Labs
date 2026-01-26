#!/bin/bash

# Centralized Syslog Setup Script for Kathara Lab
# This script configures all containers to send logs to a centralized location

# Prevent multiple runs
if [ -f /tmp/syslog_setup_done ]; then
    echo "Syslog already configured on $(hostname)"
    exit 0
fi

echo "Setting up centralized syslog for device: $(hostname)"

# Get the host IP (Docker host IP to access the mounted volume)
HOST_IP=$(ip route | grep default | awk '{print $3}' | head -1)
if [ -z "$HOST_IP" ]; then
    HOST_IP="172.17.0.1"  # Default Docker bridge IP
fi

# Function to install and configure rsyslog for centralized logging
setup_centralized_syslog() {
    # Update package lists and install rsyslog
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq > /dev/null 2>&1
    
    # Try to install rsyslog
    if apt-get install -y rsyslog > /dev/null 2>&1; then
        echo "Successfully installed rsyslog"
        
        # Create rsyslog configuration for centralized logging
        cat > /etc/rsyslog.conf << 'EOF'
# Centralized rsyslog configuration for Kathara Lab
$ModLoad imuxsock
$ModLoad imklog

# Global directives
$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat
$RepeatedMsgReduction on
$WorkDirectory /var/spool/rsyslog
$ActionQueueFileName queue
$ActionQueueMaxDiskSpace 1g
$ActionQueueSaveOnShutdown on
$ActionQueueType LinkedList
$ActionResumeRetryCount -1

# Include additional configuration files
$IncludeConfig /etc/rsyslog.d/*.conf

# Local logging (keep some local logs for debugging)
kern.*                          /var/log/kern.log
*.info;mail.none;authpriv.none;cron.none /var/log/messages
authpriv.*                      /var/log/auth.log
mail.*                          /var/log/mail.log
cron.*                          /var/log/cron.log
daemon.*                        /var/log/daemon.log

# Emergency messages to all users
*.emerg                         *

# All logs to local syslog
*.*                             /var/log/syslog

# Forward all logs to centralized location (mounted volume)
# Custom template to use IP address and simple process ID format
$template CentralizedFormatWithIP,"%TIMESTAMP% %fromhost-ip% %procid%: %msg:::drop-last-lf%\n"
# Dynamic filename based on current date - use /hostlab/syslogs for host access
$template DynamicFile,"/hostlab/syslogs/syslog-%$YEAR%-%$MONTH%-%$DAY%.log"
*.*                             ?DynamicFile;CentralizedFormatWithIP

# Network-specific logging
local0.*                        /var/log/network.log
local1.*                        /var/log/routing.log
local2.*                        /var/log/interfaces.log
EOF

        # Create directory for additional configs
        mkdir -p /etc/rsyslog.d
        
        # Create network-specific logging config
        cat > /etc/rsyslog.d/50-network.conf << 'EOF'
# Network simulation specific logging rules

# FRR daemon logs
if $programname startswith 'bgpd' then {
    /var/log/frr-bgp.log
    ?DynamicFile;CentralizedFormatWithIP
}
if $programname startswith 'ospfd' then {
    /var/log/frr-ospf.log
    ?DynamicFile;CentralizedFormatWithIP
}
if $programname startswith 'zebra' then {
    /var/log/frr-zebra.log
    ?DynamicFile;CentralizedFormatWithIP
}
if $programname startswith 'isisd' then {
    /var/log/frr-isis.log
    ?DynamicFile;CentralizedFormatWithIP
}

# Interface and network events
if $msg contains 'link' then {
    /var/log/interface-events.log
    ?DynamicFile;CentralizedFormatWithIP
}
if $msg contains 'route' then {
    /var/log/routing-events.log
    ?DynamicFile;CentralizedFormatWithIP
}
if $msg contains 'neighbor' then {
    /var/log/neighbor-events.log
    ?DynamicFile;CentralizedFormatWithIP
}

# NetworkSim tagged messages
if $syslogtag startswith 'NetworkSim' then {
    ?DynamicFile;CentralizedFormatWithIP
}
if $syslogtag startswith 'FRR' then {
    ?DynamicFile;CentralizedFormatWithIP
}
if $syslogtag startswith 'BGP' then {
    ?DynamicFile;CentralizedFormatWithIP
}
if $syslogtag startswith 'OSPF' then {
    ?DynamicFile;CentralizedFormatWithIP
}
if $syslogtag startswith 'INTERFACE' then {
    ?DynamicFile;CentralizedFormatWithIP
}
if $syslogtag startswith 'ROUTING' then {
    ?DynamicFile;CentralizedFormatWithIP
}
EOF

        # Create the syslog work directory
        mkdir -p /var/spool/rsyslog
        
        # Start rsyslog
        mkdir -p /run/rsyslog
        service rsyslog start || rsyslogd
        
        # Test rsyslog
        logger -t "NetworkSim" "Centralized syslog initialized for $(hostname) at $(date)"
        logger -p local0.info -t "NetworkSim" "Network logging ready on $(hostname)"
        
    else
        echo "Failed to install rsyslog, using fallback logging method"
        
        # Create syslog files manually
        touch /var/log/syslog
        touch /var/log/messages  
        touch /var/log/kern.log
        touch /var/log/auth.log
        touch /var/log/daemon.log
        
        # Ensure the centralized log directory exists
        mkdir -p /shared/syslogs
        
        # Create logging function that always logs to centralized location
        cat > /usr/local/bin/net_logger << 'EOF'
#!/bin/bash
# Network logging function with centralized output

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

# Cisco-style timestamp format (for message content only)
timestamp1=$(date '+%b %d %H:%M:%S')
timestamp2=$(date '+%b %d %H:%M:%S.%3N')

# Format message in Cisco style (only in the message part)
cisco_msg="*${timestamp2}: ${message}"

# Full syslog entry format: timestamp ip_address pid: cisco_message  
formatted_msg="$timestamp1 $ip_addr $pid: $cisco_msg"

# Generate dynamic filename based on current date
current_date=$(date '+%Y-%m-%d')
log_file="/shared/syslogs/syslog-${current_date}.log"

# Always log to centralized location with dynamic filename in shared directory
mkdir -p /shared/syslogs
echo "$formatted_msg" >> "$log_file"

# Also try to copy to host directory if accessible (for bridged containers)
host_log_dir="/hostlab/syslogs"
if [ -d "$host_log_dir" ] || mkdir -p "$host_log_dir" 2>/dev/null; then
    echo "$formatted_msg" >> "$host_log_dir/syslog-${current_date}.log" 2>/dev/null || true
fi

# Also log locally for debugging
echo "$formatted_msg" >> /var/log/syslog
echo "$formatted_msg" >> /var/log/messages

# Route based on tag to local files
case "$tag" in
    "NetworkSim"|"FRR"|"BGP"|"OSPF"|"ISIS"|"INTERFACE"|"ROUTING")
        echo "$formatted_msg" >> "/var/log/$(echo $tag | tr '[:upper:]' '[:lower:]').log"
        ;;
esac

# Also use system logger if available
if command -v /bin/logger >/dev/null 2>&1; then
    /bin/logger -t "$tag" "$message" 2>/dev/null || true
fi
EOF
        chmod +x /usr/local/bin/net_logger
        
        # Test the logger
        /usr/local/bin/net_logger -t "NetworkSim" "Manual centralized logging initialized for $(hostname)"
    fi
}

# Create log directories
mkdir -p /var/log
mkdir -p /shared/syslogs

# Setup syslog
setup_centralized_syslog

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
        cisco_msg="%OSPF-6-ADJCHANGE: ${message}"
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

# Override the logger command to always use centralized logging
cat > /usr/local/bin/logger << 'EOF'
#!/bin/bash
# Override logger to ensure centralized logging

# Parse arguments for compatibility with standard logger
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

# Use our centralized logger
/usr/local/bin/net_logger -t "$tag" "$message"

# Also call system logger if it exists with different name
if [ -x /bin/logger.orig ]; then
    /bin/logger.orig "$@" 2>/dev/null || true
elif [ -x /usr/bin/logger ]; then
    /usr/bin/logger "$@" 2>/dev/null || true
fi
EOF
chmod +x /usr/local/bin/logger

# Backup original logger if it exists
if [ -x /bin/logger ] && [ ! -x /bin/logger.orig ]; then
    cp /bin/logger /bin/logger.orig 2>/dev/null || true
fi

# Log the completion
if command -v log_network_event >/dev/null 2>&1; then
    log_network_event "system" "Centralized syslog setup completed for $(hostname)"
else
    /usr/local/bin/net_logger -t "NetworkSim" "Centralized syslog setup completed for $(hostname)" 2>/dev/null || echo "Centralized syslog setup completed for $(hostname)" >> /shared/syslogs/syslog-$(date '+%Y-%m-%d').log
fi

# Mark setup as complete
touch /tmp/syslog_setup_done

echo "Centralized syslog setup completed for $(hostname)"

# Ensure proper permissions for log file
chmod 666 /shared/syslogs/syslog-$(date '+%Y-%m-%d').log 2>/dev/null || true
