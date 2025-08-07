#!/bin/bash

# Auto-detect interfaces
PUB_IFACE=$(ip route get 1.1.1.1 | grep -oP 'dev \K\S+' | head -n1)
ZT_IFACE=$(ip -o link show | awk -F': ' '/zt/{print $2}' | head -n1)

# Validate interfaces
if [ -z "$PUB_IFACE" ]; then
    echo "❌ Error: Could not detect public interface"
    exit 1
fi

if [ -z "$ZT_IFACE" ]; then
    echo "⚠️  Warning: No ZeroTier interface detected. Skipping ZeroTier rules."
    ZT_IFACE=""
fi

echo "🔧 Detected interfaces:"
echo "   Public: $PUB_IFACE"
echo "   ZeroTier: $ZT_IFACE"

echo "[1/6] Reset UFW..."
ufw --force reset

echo "[2/6] Define default policies..."
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward

echo "[3/6] Allow HTTP/HTTPS on public interfaces..."
ufw allow in on $PUB_IFACE to any port 80 proto tcp
ufw allow in on $PUB_IFACE to any port 443 proto tcp

echo "[4/6] Allow SSH..."
ufw allow in on $PUB_IFACE to any port 22 proto tcp

if [ -n "$ZT_IFACE" ]; then
    echo "[5/6] Allow all traffic on ZeroTier interface..."
    ufw allow in on $ZT_IFACE
    ufw allow out on $ZT_IFACE
else
    echo "[5/6] Skipping ZeroTier rules (interface not found)"
fi

echo "[6/6] Enable UFW..."
ufw --force enable

echo "✅ Firewall configuration complete!"
echo "📊 Current UFW status:"
ufw status verbose