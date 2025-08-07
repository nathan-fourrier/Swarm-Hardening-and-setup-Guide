#!/bin/bash

# Function to calculate network CIDR from IP and prefix
calculate_network_cidr() {
    ip_with_prefix=$1

    ip=${ip_with_prefix%/*}
    prefix=${ip_with_prefix#*/}

    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"

    # Convert IP to integer
    ip_int=$(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))

    # Build subnet mask
    mask=$(( 0xFFFFFFFF << (32 - prefix) & 0xFFFFFFFF ))

    # Calculate network
    network=$(( ip_int & mask ))

    n1=$(( (network >> 24) & 0xFF ))
    n2=$(( (network >> 16) & 0xFF ))
    n3=$(( (network >> 8) & 0xFF ))
    n4=$(( network & 0xFF ))

    echo "$n1.$n2.$n3.$n4/$prefix"
}

echo "=== ZeroTier Info ==="
zt_iface=$(ip -o link show | awk -F': ' '/zt/{print $2}' | head -n1)

if [ -n "$zt_iface" ]; then
    zt_ip_cidr=$(ip -4 addr show dev "$zt_iface" | awk '/inet / {print $2}')
    zt_ip=${zt_ip_cidr%/*}
    zt_network_id=$(sudo zerotier-cli listnetworks | grep "$zt_iface" | awk '{print $3}')
    zt_network_cidr=$(calculate_network_cidr "$zt_ip_cidr")

    echo "Interface   : $zt_iface"
    echo "IP Address  : $zt_ip"
    echo "Network CIDR: $zt_network_cidr"
    echo "Network ID  : $zt_network_id"
else
    echo "No ZeroTier interface found."
fi

echo ""
echo "=== Public Interface Info ==="
public_iface=$(ip route get 1.1.1.1 | grep -oP 'dev \K\S+')

if [ -n "$public_iface" ]; then
    public_ip_cidr=$(ip -4 addr show dev "$public_iface" | awk '/inet / {print $2}')
    public_ip=${public_ip_cidr%/*}
    public_network_cidr=$(calculate_network_cidr "$public_ip_cidr")

    echo "Interface   : $public_iface"
    echo "IP Address  : $public_ip"
    echo "Network CIDR: $public_network_cidr"
else
    echo "No public interface found."
fi