#!/bin/bash

# 检查是否启用自动模式
AUTO_MODE=false
[[ "$1" == "--auto" ]] && AUTO_MODE=true

USER="root"
PASS="aj8888"
SOCKS5_COUNT=1
COUNTRY=""

function disable_ipv6() {
  echo "🚫 正在禁用 IPv6..."

  # 临时禁用（立即生效）
  sysctl -w net.ipv6.conf.all.disable_ipv6=1
  sysctl -w net.ipv6.conf.default.disable_ipv6=1

  # 永久禁用（写入配置文件）
  grep -q "disable_ipv6" /etc/sysctl.conf || cat <<EOF >> /etc/sysctl.conf

# 禁用 IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

  # 应用配置
  sysctl -p
}

function enable_bbr() {
  echo "⚙️ 正在启用 BBR 拥塞控制..."
  sysctl -w net.core.default_qdisc=fq
  sysctl -w net.ipv4.tcp_congestion_control=bbr
  grep -q "net.core.default_qdisc" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
}

function get_country_code() {
  CODE=$(curl -s https://ipinfo.io/country)
  echo $CODE
}


function detect_or_choose_country() {
  if $AUTO_MODE; then
    COUNTRY=$(get_country_code)
    echo "🌍 自动模式：使用检测到的国家代码 $COUNTRY"
    return
  fi
  DETECTED=$(get_country_code)
  echo "🌍 检测到当前 IP 所在国家代码为：$DETECTED"
  read -p "👉 是否使用检测到的国家代码？ 按回车默认Y (Y/n): " use_detect
  if [[ "$use_detect" =~ ^[Nn]$ ]]; then
    echo "可选国家代码：US UK DE FR JP MX ES"
    read -p "请输入国家代码: " COUNTRY
  else
    COUNTRY="$DETECTED"
  fi
}

function install_xray() {
  detect_or_choose_country
  if $AUTO_MODE; then
    SOCKS5_COUNT=1
    echo "🔢 自动模式：使用默认节点数量 $SOCKS5_COUNT"
  else
    read -p "请输入要创建的节点数量 按回车默认1 （默认: 1）: " count
    SOCKS5_COUNT=${count:-1}
  fi

  disable_ipv6
  enable_bbr

  bash <(curl -sL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh) @ install

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
    [US]='["tls://8.8.8.8","tls://8.8.4.4","localhost"]'
    [UK]='["tls://1.1.1.1","tls://1.0.0.1","localhost"]'
    [DE]='["tls://9.9.9.9","tls://149.112.112.112","localhost"]'
    [FR]='["tls://80.67.169.12","tls://80.67.169.40","localhost"]'
    [JP]='["tls://210.130.1.1","tls://210.130.1.2","localhost"]'
    [MX]='["tls://8.8.8.8","tls://8.8.4.4","localhost"]'
    [ES]='["tls://62.36.225.150","tls://8.8.8.8","localhost"]'
  )

  TIMEZONE=${TIMEZONES[$COUNTRY]}
  DNS_JSON=${DNS_SERVERS[$COUNTRY]}

  echo "⏱ 设置时区：$TIMEZONE"
  timedatectl set-timezone "$TIMEZONE"

  echo "📦 安装依赖..."
  sudo apt update && sudo apt install -y cron uuid-runtime unzip socat certbot curl dnsutils qrencode jq

  echo "🔧 配置防火墙..."
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

  echo "🧰 生成配置..."
  INBOUNDS_JSON='['
  for ((i=0; i<SOCKS5_COUNT; i++)); do
    PORT=$((10808 + i))
    INBOUNDS_JSON+="
    {
      \"listen\": \"0.0.0.0\",
      \"port\": $PORT,
      \"protocol\": \"socks\",
      \"settings\": {
        \"auth\": \"password\",
        \"accounts\": [
          {
            \"user\": \"$USER\",
            \"pass\": \"$PASS\"
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
  INBOUNDS_JSON="${INBOUNDS_JSON%,}]"

  cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "loglevel": "debug",
    "access": "/usr/local/etc/xray/access.log",
    "error": "/usr/local/etc/xray/error.log"
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "domain": ["geosite:google","geosite:akamai","geosite:amazon","geosite:apple","geosite:twitter","geosite:facebook","geosite:tiktok"],
        "outboundTag": "direct",
        "type": "field"
      },
      {
        "domain": ["regexp:^.*(tik|byte|paypal|appsflyer|gstatic|akamai).*\$"],
        "outboundTag": "direct",
        "type": "field"
      },
      {
        "protocol": ["bittorrent"],
        "outboundTag": "blocked",
        "type": "field"
      },
      {
        "domain": ["geosite:category-ads-all"],
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

  echo "🚀 启动 Xray 服务..."
  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable xray
  systemctl restart xray

  echo "📅 设置每周清空日志任务..."
  (crontab -l 2>/dev/null; echo "0 0 * * 1 echo '' > /usr/local/etc/xray/access.log && echo '' > /usr/local/etc/xray/error.log") | crontab -

  echo "✅ 所有节点安装完成！"
  show_nodes
}

function show_nodes() {
  CONFIG_PATH="/usr/local/etc/xray/config.json"
  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "❌ 未找到配置文件，可能尚未安装节点。"
    return
  fi

  IN_IP=$(curl -s ifconfig.me)
  mapfile -t INBOUNDS < <(jq -c '.inbounds[]' "$CONFIG_PATH")

  echo "📋 当前所有节点信息："

  for inbound in "${INBOUNDS[@]}"; do
    PORT=$(echo "$inbound" | jq -r '.port')
    ENCODED_PASS=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${PASS}'))")
    LINK="socks://${USER}:${ENCODED_PASS}@${IN_IP}:${PORT}#SOCKS5-${COUNTRY}-${PORT}"
    echo -e "\n🌐 节点名称: SOCKS5-${COUNTRY}-${PORT}"
    echo "🔗 连接地址: $LINK"
    echo "📎 二维码:"
    echo "$LINK" | qrencode -t ANSIUTF8
  done

  echo -e "\n✅ 共显示 ${#INBOUNDS[@]} 个节点。"
}

function uninstall_xray() {
  echo "⚠️ 正在卸载 Xray..."
  systemctl stop xray
  systemctl disable xray
  rm -rf /usr/local/bin/xray /usr/local/etc/xray /etc/systemd/system/xray.service
  echo "✅ Xray 卸载完成。"
}

function reinstall_xray() {
  uninstall_xray
  install_xray
}

function main_menu() {
  if $AUTO_MODE; then
    echo "🟢 自动模式已启用，开始默认安装..."
    install_xray
    exit 0
  fi
  clear
  echo "========= Socks5 节点部署脚本 ========="
  echo "1. 安装节点"
  echo "2. 重新安装节点（清除后重装）"
  echo "3. 查看所有节点信息"
  echo "4. 卸载所有节点"
  echo "======================================="
  echo "by:TikTok-AJ"
  echo "✅ 快捷运行命令 AJ (不分大小写)"
  read -p "请输入选项(1-4) [默认: 1]: " choice
  choice=${choice:-1}
  case "$choice" in
    1) install_xray ;;
    2) reinstall_xray ;;
    3) show_nodes ;;
    4) uninstall_xray ;;
    *) echo "无效输入，退出"; exit 1 ;;
  esac
}

main_menu



# ✅ 安装脚本为 ja 命令并创建大写 AJ 快捷方式（不区分大小写）
SCRIPT_PATH=$(realpath "$0")
if [[ "$SCRIPT_PATH" != "/usr/local/bin/aj" ]]; then
  echo "📌 正在安装快捷命令：ja 和 AJ"
  sudo install -m 755 "$SCRIPT_PATH" /usr/local/bin/aj && sudo ln -sf /usr/local/bin/aj /usr/local/bin/AJ
  echo "✅ 你现在可以通过命令 ja 或 AJ 来快速运行此脚本。"
fi
