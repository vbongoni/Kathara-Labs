# Kathara Lab Centralized Logging

This lab collects all container syslog messages into date-based files: `syslogs/syslog-YYYY-MM-DD.log`

## Quick Start

```bash
# Start lab with logging
./manage_logs.sh start

# Monitor logs in real-time
./manage_logs.sh monitor

# Check status
./manage_logs.sh status

# Stop lab
./manage_logs.sh stop
```

## All Commands

```bash
./manage_logs.sh start     # Start lab and setup logging
./manage_logs.sh sync      # Sync logs from containers to host
./manage_logs.sh monitor   # Monitor today's logs in real-time
./manage_logs.sh list      # List all available log files
./manage_logs.sh view      # View today's logs
./manage_logs.sh test      # Generate test logs
./manage_logs.sh status    # Show current status
./manage_logs.sh stop      # Stop lab and collect final logs
./manage_logs.sh clean     # Remove old log files
```

## Log Format

```
Aug 20 22:32:03 r11 NetworkSim[22166]: %SYS-5-CONFIG_I: Interface eth0 configured: 100.10.1.11/24
```

That's it! Single tool for everything.
