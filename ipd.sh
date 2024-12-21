#!/bin/bash

# Define password
CORRECT_PASSWORD="wuyue4869"

# Password verification function
verify_password() {
    read -sp "请输入密码: " input_password
    echo
    if [[ "$input_password" != "$CORRECT_PASSWORD" ]]; then
        echo "密码错误！"
        exit 1
    fi
    echo "密码验证成功！正在开始配置..."
    echo
}

# Verify password
verify_password

# Define VPN and SOCKS5 configuration
VPN_IP_RANGE="10.0.1.1-10.0.1.80"
VPN_GATEWAY="10.0.1.254"
VPN_DNS1="223.5.5.5"
VPN_DNS2="8.8.8.8"

# Define the number of VPN users to create
VPN_USER_COUNT=80

# Install necessary packages
sudo apt update
sudo apt install -y iptables-persistent redsocks xl2tpd

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Configure xl2tpd
cat << EOF > /etc/xl2tpd/xl2tpd.conf
[global]
ipsec saref = yes

[lns default]
ip range = $VPN_IP_RANGE
local ip = $VPN_GATEWAY
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

cat << EOF > /etc/ppp/options.xl2tpd
ipcp-accept-local
ipcp-accept-remote
ms-dns $VPN_DNS1
ms-dns $VPN_DNS2
noccp
auth
crtscts
idle 1800
mtu 1460
mru 1460
nodefaultroute
debug
lock
proxyarp
connect-delay 5000
EOF

# Add VPN users with specific IP assignments
for i in $(seq 1 $VPN_USER_COUNT); do
    echo "user$i * pass$i 10.0.1.$i" >> /etc/ppp/chap-secrets
done

# 获取主网络接口
INTERFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')

# 配置 iptables
iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -o ${INTERFACE} -j MASQUERADE

# 配置路由表和策略路由
for i in $(seq 1 $VPN_USER_COUNT); do
    # 创建新的路由表
    echo "$((100+i)) vpn$i" >> /etc/iproute2/rt_tables
    
    # 添加策略路由
    ip rule add from 10.0.1.$i table vpn$i
    
    # 重定向流量到 redsocks
    iptables -t nat -A PREROUTING -s 10.0.1.$i -p tcp -j REDIRECT --to-port $((40000 + i))
done

# Save iptables rules
iptables-save > /etc/iptables/rules.v4

# Note: redsocks.conf will be replaced manually later

# Start services
systemctl restart xl2tpd
systemctl start redsocks
systemctl restart redsocks
systemctl enable xl2tpd redsocks

# 启用 IP 转发
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo "配置完成。L2TP VPN服务已安装和配置，共设置了 $VPN_USER_COUNT 个用户。"
echo "请手动替换 /etc/redsocks.conf 文件，然后重启 redsocks 服务。"