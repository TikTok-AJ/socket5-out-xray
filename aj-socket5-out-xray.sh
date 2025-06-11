#!/bin/bash
# Usage: ./xray_setup.sh COUNTRY_CODE INBOUND_DOMAIN OUTBOUND_DOMAIN [SOCKS5_COUNT]
# COUNTRY_CODE 支持 US UK DE FR JP MX
echo "禁用 IPv6..."

# 临时禁用（立即生效）
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1

# 永久禁用（写入配置文件）
grep -q "disable_ipv6" /etc/sysctl.conf || cat <<EOF >> /etc/sysctl.conf

# 禁用 IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

# 应用 sysctl 设置
sysctl -p

COUNTRY=$1
SOCKS5_COUNT=${2:-1}  # 默认生成1个 SOCKS5 配置
EMAIL="0000000@gmail.com"

if [[ -z "$COUNTRY" ]]; then
  echo "Usage: $0 COUNTRY_CODE INBOUND_DOMAIN OUTBOUND_DOMAIN [SOCKS5_COUNT]"
  echo "Supported COUNTRY_CODE: US UK DE FR JP MX ES"
  exit 1
fi

declare -A TIMEZONES=(
  [US]="America/Los_Angeles"
  [UK]="Europe/London"
  [DE]="Europe/Berlin"
  [FR]="Europe/Paris"
  [JP]="Asia/Tokyo"
  [MX]="America/Mexico_City"
  [ES]="Europe/Madrid"
)

declare -A DNS_SERVERS=(
  [US]='["tls://8.8.8.8","tls://8.8.4.4","8.8.8.8","localhost"]'
  [UK]='["tls://1.1.1.1","tls://1.0.0.1","1.1.1.1","localhost"]'
  [DE]='["tls://9.9.9.9","tls://149.112.112.112","9.9.9.9","localhost"]'
  [FR]='["tls://80.67.169.12","tls://80.67.169.40","80.67.169.12","localhost"]'
  [JP]='["tls://210.130.1.1","tls://210.130.1.2","210.130.1.1","localhost"]'
  [MX]='["tls://8.8.8.8","tls://8.8.4.4","8.8.8.8","localhost"]'
  [ES]='["tls://62.36.225.150","tls://8.8.8.8","62.36.225.150","localhost"]'
)

declare -A ACCEPT_LANG=(
  [US]='"en-US,en;q=0.9"'
  [UK]='"en-GB,en;q=0.9"'
  [DE]='"de-DE,de;q=0.9,en;q=0.8"'
  [FR]='"fr-FR,fr;q=0.9,en;q=0.8"'
  [JP]='"ja-JP,ja;q=0.9,en;q=0.8"'
  [MX]='"es-MX,es;q=0.9,en;q=0.8"'
  [ES]='"es-ES,es;q=0.9,en;q=0.8"'
)


TIMEZONE=${TIMEZONES[$COUNTRY]}
DNS_JSON=${DNS_SERVERS[$COUNTRY]}
LANG_HEADER=${ACCEPT_LANG[$COUNTRY]}

if [[ -z "$TIMEZONE" || -z "$DNS_JSON" || -z "$LANG_HEADER" ]]; then
  echo "Unsupported COUNTRY_CODE: $COUNTRY"
  exit 2
fi

echo "设置时区为 $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"

echo "更新并安装必要软件"
sudo apt update && sudo apt install -y cron uuid-runtime unzip socat certbot curl dnsutils

if ! systemctl is-enabled --quiet cron; then
  systemctl enable cron && systemctl start cron
fi

echo "安装 Xray"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

echo "修改 Xray 服务权限为 root"
sed -i 's/nobody/root/g' /etc/systemd/system/xray.service



# 配置防火墙
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 53/udp
START_PORT=10808
END_PORT=$((START_PORT + SOCKS5_COUNT - 1))
ufw allow $START_PORT:$END_PORT/tcp
ufw allow $START_PORT:$END_PORT/udp
ufw --force enable

CONFIG_PATH="/usr/local/etc/xray/config.json"
mkdir -p /usr/local/etc/xray

# 构造多个inbound配置JSON片段
INBOUNDS_JSON='['
# 固定 dokodemo-door 入站
INBOUNDS_JSON+=''
ROUTING_RULES=()

# 循环生成 SOCKS5 入站配置
for ((i=0; i<SOCKS5_COUNT; i++))
do
  PORT=$((START_PORT + i))
  INBOUNDS_JSON+="
    {
      \"listen\": \"0.0.0.0\",
      \"port\": $PORT,
      \"protocol\": \"socks\",
      \"settings\": {
        \"auth\": \"password\",
        \"accounts\": [
          {
            \"user\": \"wukunpeng\",
            \"pass\": \"aj8888\"
          }
        ],
        \"udp\": true
      },
      \"tag\": \"inbound-$PORT\",
      \"sniffing\": {
        \"enabled\": true,
        \"destOverride\": [\"http\", \"tls\"]
      }
    },"

done

# 去掉最后的逗号
INBOUNDS_JSON="${INBOUNDS_JSON%,}]"

cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "loglevel": "debug",
    "error": "/usr/local/etc/xray/error.log"
  },
   "routing": {
        "domainStrategy": "AsIs",
        "rules": [
          
            {
                "domain": [
                    "geosite:google",
                    "geosite:akamai",
                    "geosite:amazon",
                    "geosite:apple",
                    "geosite:twitter",
                    "geosite:facebook",
 		    "geosite:tiktok"
                ],
                "outboundTag": "direct",
                "type": "field"
            },
            {
                "domain": [
                    "regexp:^.*(tik|ibyted|byte|tt|lem|musical|braintreegateway|topbuzzcdn|muscdn|gstatic|app-analytics-services|paypal|shuftipro|appsflyersdk|snapkit|akamai).*$"
                ],
                "outboundTag": "direct",
                "type": "field"
            },
            {
                "protocol": [
                    "bittorrent"
                ],
                "outboundTag": "blocked",
                "type": "field"
            },
  	       {
                "domain": [
                    "geosite:category-ads-all"
                ],
                "outboundTag": "blocked",
                "type": "field"
            },
            {
                "type": "field",
                "network": "tcp,udp",
                "outboundTag": "direct"
            }
        ]
    },
  "dns": {
    "servers": $DNS_JSON
  },
  "inbounds": $INBOUNDS_JSON,
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ]
}
EOF

# 启用 BBR
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr
grep -q "net.core.default_qdisc" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

echo "Socks5 节点已启动，请使用 wukunpeng / aj8888 进行连接"
IN_IP=$(curl -s ifconfig.me)
#!/bin/bash
# Usage: ./xray_setup.sh COUNTRY_CODE INBOUND_DOMAIN OUTBOUND_DOMAIN [SOCKS5_COUNT]
# COUNTRY_CODE 支持 US UK DE FR JP MX
# EMAIL 固定为 1067109371@qq.com
echo "禁用 IPv6..."

# 临时禁用（立即生效）
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1

# 永久禁用（写入配置文件）
grep -q "disable_ipv6" /etc/sysctl.conf || cat <<EOF >> /etc/sysctl.conf

# 禁用 IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

# 应用 sysctl 设置
sysctl -p

COUNTRY=$1
SOCKS5_COUNT=${2:-1}  # 默认生成1个 SOCKS5 配置
EMAIL="1067109371@qq.com"

if [[ -z "$COUNTRY" ]]; then
  echo "Usage: $0 COUNTRY_CODE INBOUND_DOMAIN OUTBOUND_DOMAIN [SOCKS5_COUNT]"
  echo "Supported COUNTRY_CODE: US UK DE FR JP MX ES"
  exit 1
fi

declare -A TIMEZONES=(
  [US]="America/Los_Angeles"
  [UK]="Europe/London"
  [DE]="Europe/Berlin"
  [FR]="Europe/Paris"
  [JP]="Asia/Tokyo"
  [MX]="America/Mexico_City"
  [ES]="Europe/Madrid"
)

declare -A DNS_SERVERS=(
  [US]='["tls://8.8.8.8","tls://8.8.4.4","8.8.8.8","localhost"]'
  [UK]='["tls://1.1.1.1","tls://1.0.0.1","1.1.1.1","localhost"]'
  [DE]='["tls://9.9.9.9","tls://149.112.112.112","9.9.9.9","localhost"]'
  [FR]='["tls://80.67.169.12","tls://80.67.169.40","80.67.169.12","localhost"]'
  [JP]='["tls://210.130.1.1","tls://210.130.1.2","210.130.1.1","localhost"]'
  [MX]='["tls://8.8.8.8","tls://8.8.4.4","8.8.8.8","localhost"]'
  [ES]='["tls://62.36.225.150","tls://8.8.8.8","62.36.225.150","localhost"]'
)

declare -A ACCEPT_LANG=(
  [US]='"en-US,en;q=0.9"'
  [UK]='"en-GB,en;q=0.9"'
  [DE]='"de-DE,de;q=0.9,en;q=0.8"'
  [FR]='"fr-FR,fr;q=0.9,en;q=0.8"'
  [JP]='"ja-JP,ja;q=0.9,en;q=0.8"'
  [MX]='"es-MX,es;q=0.9,en;q=0.8"'
  [ES]='"es-ES,es;q=0.9,en;q=0.8"'
)


TIMEZONE=${TIMEZONES[$COUNTRY]}
DNS_JSON=${DNS_SERVERS[$COUNTRY]}
LANG_HEADER=${ACCEPT_LANG[$COUNTRY]}

if [[ -z "$TIMEZONE" || -z "$DNS_JSON" || -z "$LANG_HEADER" ]]; then
  echo "Unsupported COUNTRY_CODE: $COUNTRY"
  exit 2
fi

echo "设置时区为 $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"

echo "更新并安装必要软件"
sudo apt update && sudo apt install -y cron uuid-runtime unzip socat certbot curl dnsutils

if ! systemctl is-enabled --quiet cron; then
  systemctl enable cron && systemctl start cron
fi

echo "安装 Xray"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

echo "修改 Xray 服务权限为 root"
sed -i 's/nobody/root/g' /etc/systemd/system/xray.service



# 配置防火墙
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 53/udp
START_PORT=10808
END_PORT=$((START_PORT + SOCKS5_COUNT - 1))
ufw allow $START_PORT:$END_PORT/tcp
ufw allow $START_PORT:$END_PORT/udp
ufw --force enable

CONFIG_PATH="/usr/local/etc/xray/config.json"
mkdir -p /usr/local/etc/xray

# 构造多个inbound配置JSON片段
INBOUNDS_JSON='['
# 固定 dokodemo-door 入站
INBOUNDS_JSON+=''
ROUTING_RULES=()

# 循环生成 SOCKS5 入站配置
for ((i=0; i<SOCKS5_COUNT; i++))
do
  PORT=$((START_PORT + i))
  INBOUNDS_JSON+="
    {
      \"listen\": \"0.0.0.0\",
      \"port\": $PORT,
      \"protocol\": \"socks\",
      \"settings\": {
        \"auth\": \"password\",
        \"accounts\": [
          {
            \"user\": \"wukunpeng\",
            \"pass\": \"aj8888\"
          }
        ],
        \"udp\": true
      },
      \"tag\": \"inbound-$PORT\",
      \"sniffing\": {
        \"enabled\": true,
        \"destOverride\": [\"http\", \"tls\"]
      }
    },"

done

# 去掉最后的逗号
INBOUNDS_JSON="${INBOUNDS_JSON%,}]"

cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "loglevel": "debug",
    "error": "/usr/local/etc/xray/error.log"
  },
   "routing": {
        "domainStrategy": "AsIs",
        "rules": [
          
            {
                "domain": [
                    "geosite:google",
                    "geosite:akamai",
                    "geosite:amazon",
                    "geosite:apple",
                    "geosite:twitter",
                    "geosite:facebook",
 		    "geosite:tiktok"
                ],
                "outboundTag": "direct",
                "type": "field"
            },
            {
                "domain": [
                    "regexp:^.*(tik|ibyted|byte|tt|lem|musical|braintreegateway|topbuzzcdn|muscdn|gstatic|app-analytics-services|paypal|shuftipro|appsflyersdk|snapkit|akamai).*$"
                ],
                "outboundTag": "direct",
                "type": "field"
            },
            {
                "protocol": [
                    "bittorrent"
                ],
                "outboundTag": "blocked",
                "type": "field"
            },
  	       {
                "domain": [
                    "geosite:category-ads-all"
                ],
                "outboundTag": "blocked",
                "type": "field"
            },
            {
                "type": "field",
                "network": "tcp,udp",
                "outboundTag": "direct"
            }
        ]
    },
  "dns": {
    "servers": $DNS_JSON
  },
  "inbounds": $INBOUNDS_JSON,
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ]
}
EOF

# 启用 BBR
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr
grep -q "net.core.default_qdisc" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

echo "Socks5 节点已启动，请使用 wukunpeng / aj8888 进行连接"
IN_IP=$(curl -s ifconfig.me)
USER="wukunpeng"
PASS="aj8888"
# 生成所有 SOCKS5 链接并保存
for ((i=0; i<SOCKS5_COUNT; i++))
do
  PORT=$((START_PORT + i))
  ENCODED_PASS=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${PASS}'))")
  LINK="socks://${USER}:${ENCODED_PASS}@${IN_IP}:${PORT}#SOCKS5-${COUNTRY}-${IN_IP}-${PORT}"
  echo "$LINK"
done


# 配置定时任务每周清理日志
(crontab -l 2>/dev/null; \
 echo "0 0 * * 1 echo '' > /usr/local/etc/xray/access.log && echo '' > /usr/local/etc/xray/error.log") | crontab -

echo "部署完成！"

# 配置定时任务每周清理日志
(crontab -l 2>/dev/null; \
 echo "0 0 * * 1 echo '' > /usr/local/etc/xray/access.log && echo '' > /usr/local/etc/xray/error.log") | crontab -

echo "部署完成！"
