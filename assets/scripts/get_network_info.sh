#!/bin/bash

# Function to calculate network CIDR from IP and prefix
calculate_network_cidr() {
    local ip_with_prefix=$1

    if [[ ! "$ip_with_prefix" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        echo "❌ Invalid IP format: $ip_with_prefix"
        return 1
    fi

    local ip=${ip_with_prefix%/*}
    local prefix=${ip_with_prefix#*/}

    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"

    # Convert IP to integer
    local ip_int=$(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))

    # Build subnet mask
    local mask=$(( 0xFFFFFFFF << (32 - prefix) & 0xFFFFFFFF ))

    # Calculate network
    local network=$(( ip_int & mask ))

    local n1=$(( (network >> 24) & 0xFF ))
    local n2=$(( (network >> 16) & 0xFF ))
    local n3=$(( (network >> 8) & 0xFF ))
    local n4=$(( network & 0xFF ))

    echo "$n1.$n2.$n3.$n4/$prefix"
}

echo "🔍 Network Information Script"
echo "=============================="

echo ""
echo "=== ZeroTier Info ==="
zt_iface=$(ip -o link show | awk -F': ' '/zt/{print $2}' | head -n1)

if [ -n "$zt_iface" ]; then
    zt_ip_cidr=$(ip -4 addr show dev "$zt_iface" | awk '/inet / {print $2}')
    if [ -n "$zt_ip_cidr" ]; then
        zt_ip=${zt_ip_cidr%/*}
        zt_network_id=$(sudo zerotier-cli listnetworks | grep "$zt_iface" | awk '{print $3}')
        zt_network_cidr=$(calculate_network_cidr "$zt_ip_cidr")

        echo "✅ Interface   : $zt_iface"
        echo "✅ IP Address  : $zt_ip"
        echo "✅ Network CIDR: $zt_network_cidr"
        echo "✅ Network ID  : $zt_network_id"
    else
        echo "⚠️  ZeroTier interface found but no IP assigned"
    fi
else
    echo "❌ No ZeroTier interface found."
fi

echo ""
echo "=== Public Interface Info ==="
public_iface=$(ip route get 1.1.1.1 | grep -oP 'dev \K\S+')

if [ -n "$public_iface" ]; then
    public_ip_cidr=$(ip -4 addr show dev "$public_iface" | awk '/inet / {print $2}')
    if [ -n "$public_ip_cidr" ]; then
        public_ip=${public_ip_cidr%/*}
        public_network_cidr=$(calculate_network_cidr "$public_ip_cidr")

        echo "✅ Interface   : $public_iface"
        echo "✅ IP Address  : $public_ip"
        echo "✅ Network CIDR: $public_network_cidr"
    else
        echo "⚠️  Public interface found but no IP assigned"
    fi
else
    echo "❌ No public interface found."
fi

echo ""
echo "=== Summary ==="
echo "Use these values in your SSH configuration:"
if [ -n "$zt_network_cidr" ]; then
    echo "ZeroTier CIDR: $zt_network_cidr"
fi
if [ -n "$public_network_cidr" ]; then
    echo "Public CIDR: $public_network_cidr"
fi