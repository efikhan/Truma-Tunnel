#!/bin/bash

# Corrected version of paqet.sh

# Set firewall rules

# Flush existing rules
iptables -F

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow incoming traffic on specified ports (e.g., 80, 443)
ipiptables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT

# Drop other incoming traffic
iptables -A INPUT -j DROP

# Set proper MTU handling
# Adjust MTU size if necessary (for example, on a PPPoE connection)
MTU_SIZE=1400
ip link set dev eth0 mtu $MTU_SIZE

# Box drawing symbols
# This is an example of complete box drawing
echo -e "┌────────────────────────────────────────────┐\n│              PAQET Script                  │\n├────────────────────────────────────────────┤\n│ Rule 1: Allow established connections.      │\n│ Rule 2: Allow HTTP/HTTPS traffic.          │\n│ Rule 3: Drop other traffic.                 │\n├────────────────────────────────────────────┤\n│ MTU Size set to: $MTU_SIZE bytes            │\n└────────────────────────────────────────────┘"