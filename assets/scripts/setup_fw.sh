#!/bin/bash

PUB_IFACE="ens3"         # Replace with public interface
ZT_IFACE="ztr2qxgeyd"    # Replace with ZeroTier interface

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

echo "[5/6] Allow all traffic on ZeroTier interface..."
ufw allow in on $ZT_IFACE
ufw allow out on $ZT_IFACE

echo "[6/6] Enable UFW..."
ufw --force enable
ufw status verbose