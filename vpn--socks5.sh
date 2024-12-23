#!/bin/bash
# 定义密码
CORRECT_PASSWORD="wuyue4869"

# 密码验证函数
verify_password() {
    read -sp "请输入密码: " input_password
    echo
    if [[ " $input_password" != " $CORRECT_PASSWORD" ]]; then
        echo "密码错误！"
        exit 1
    fi
    echo "密码验证成功！正在开始配置..."
    echo
}

# 验证密码
verify_password
# 定义VPN和SOCKS5配置
VPN_IP_RANGE="10.0.1.2-10.0.1.200"
VPN_LOCAL_IP="10.0.1.1"
VPN_DNS1="223.5.5.5"
VPN_DNS2="8.8.8.8"

# 定义要创建的VPN用户数量
VPN_USER_COUNT=80

# 定义SOCKS5代理配置
declare -A SOCKS5_CONFIGS
for i in $(seq 1 $VPN_USER_COUNT); do
    SOCKS5_CONFIGS[$i]="127.0.0.1 8080 admin admin"
done

# 安装必要的软件包
sudo apt update
sudo apt install -y iptables-persistent redsocks xl2tpd

# 启用IP转发
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# 配置xl2tpd
cat << EOF > /etc/xl2tpd/xl2tpd.conf
[global]
ipsec saref = yes

[lns default]
ip range = $VPN_IP_RANGE
local ip = $VPN_LOCAL_IP
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

# 添加VPN用户
for i in $(seq 1 $VPN_USER_COUNT); do
    echo "user$i * pass$i *" >> /etc/ppp/chap-secrets
done

# 自动获取第一个活动的网络接口名称
INTERFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')

# 配置iptables
iptables -t nat -A POSTROUTING -s ${VPN_LOCAL_IP%.*}.0/24 -o ${INTERFACE} -j MASQUERADE

# 配置路由表和策略路由
for i in $(seq 1 $VPN_USER_COUNT); do
    iptables -t mangle -A PREROUTING -s ${VPN_LOCAL_IP%.*}.$((i+1)) -j MARK --set-mark $i
    echo "$((100+i)) vpn$i" >> /etc/iproute2/rt_tables
    ip rule add fwmark $i table vpn$i
done

# 保存iptables规则
iptables-save > /etc/iptables/rules.v4

# 配置redsocks
cat << EOF > /etc/redsocks.conf
base {
    log_debug = on;
    log_info = on;
    log = "file:/var/log/redsocks.log";
    daemon = on;
    redirector = iptables;
}
EOF

for i in "${!SOCKS5_CONFIGS[@]}"; do
    read -r ip port username password <<< "${SOCKS5_CONFIGS[$i]}"
    cat << EOF >> /etc/redsocks.conf

redsocks {
    local_ip = 0.0.0.0;
    local_port = $((40001 + i));
    ip = $ip;
    port = $port;
    type = socks5;
    login = "$username";
    password = "$password";
}
EOF
    iptables -t nat -A PREROUTING -p tcp -m mark --mark $i -j REDIRECT --to-port $((40000 + i))
done

# 启动服务
systemctl restart xl2tpd
systemctl start redsocks
systemctl restart redsocks
systemctl enable xl2tpd redsocks


echo "配置完成。L2TP VPN服务已安装和配置，共设置了 $VPN_USER_COUNT 个用户。"