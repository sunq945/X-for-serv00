#!/bin/bash
SERV00PASSWORD=${SERV00PASSWORD:-'password'}

USERNAME=$(whoami)
UUID=${UUID:-'de04add9-5c68-8bab-950c-08cd5320df18'}
USERNAME_DOMAIN=$(whoami | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
WORKDIR="/home/${USERNAME}/domains/${USERNAME_DOMAIN}.serv00.net/public_nodejs"

set_language() {
    devil lang set english
}

set_domain_dir() {
    local DOMAIN="${USERNAME_DOMAIN}.serv00.net"
    if devil www list | grep nodejs | grep "/domains/${DOMAIN}" && [ -d "${WORKDIR}" ]; then
        if [ ! -d ${WORKDIR}/public ]; then
            git clone https://github.com/k0baya/momotap ${WORKDIR}/public
        fi
        return 0
    else
        echo "正在检测 NodeJS 环境，请稍候..."
        nohup devil www del ${DOMAIN} >/dev/null 2>&1
        nohup rm -rf ${WORKDIR} >/dev/null 2>&1
        devil www add ${DOMAIN} nodejs /usr/local/bin/node22
        rm -rf ${WORKDIR}/public
        git clone https://github.com/k0baya/momotap ${WORKDIR}/public
    fi
}

reserve_port() {
    local needed_udp_ports=2
    local needed_tcp_ports=1

    if [ $needed_udp_ports -lt 0 ] || [ $needed_tcp_ports -lt 0 ] || [ $((needed_udp_ports + needed_tcp_ports)) -gt 3 ]; then
        echo "错误：需要的端口数量设置不合理"
        exit 1
    fi

    local port_list
    local port_count
    local current_port
    local max_attempts
    local attempts

    local add_port
    add_port() {
        local port=$1
        local type=$2
        local result=$(devil port add "$type" "$port")
        echo "尝试添加预留 $type 端口 $port: $result" 
    }

    local delete_port
    delete_port() {
        local port=$1
        local type=$2
        local result=$(devil port del "$type" "$port")
        echo "删除 $type 端口 $port: $result"
    }

    update_port_list() {
        port_list=$(devil port list)
        port_count=$(echo "$port_list" | grep -c 'udp\|tcp')
    }

    update_port_list

    udp_count=$(echo "$port_list" | grep -c 'udp')
    tcp_count=$(echo "$port_list" | grep -c 'tcp')

    if [ $udp_count -gt $needed_udp_ports ]; then
        to_delete=$((udp_count - needed_udp_ports))
        while [ $to_delete -gt 0 ]; do
            UDP_PORT=$(echo "$port_list" | grep 'udp' | awk 'NR==1{print $1}')
            echo "需要删除多余的 UDP 端口 $UDP_PORT"
            delete_port $UDP_PORT "udp"
            update_port_list
            udp_count=$(echo "$port_list" | grep -c 'udp')
            to_delete=$((to_delete - 1))
        done
    fi

    if [ $tcp_count -gt $needed_tcp_ports ]; then
        to_delete=$((tcp_count - needed_tcp_ports))
        while [ $to_delete -gt 0 ]; do
            TCP_PORT=$(echo "$port_list" | grep 'tcp' | awk 'NR==1{print $1}')
            echo "需要删除多余的 TCP 端口 $TCP_PORT"
            delete_port $TCP_PORT "tcp"
            update_port_list
            tcp_count=$(echo "$port_list" | grep -c 'tcp')
            to_delete=$((to_delete - 1))
        done
    fi

    update_port_list
    total_ports=$(echo "$port_list" | grep -c 'udp\|tcp')

    needed_ports=$((needed_udp_ports + needed_tcp_ports))
    while [ $total_ports -lt $needed_ports ]; do
        start_port=$(( RANDOM % 63077 + 1024 )) 

        if [ $start_port -le 32512 ]; then
            current_port=$start_port
            increment=1
        else
            current_port=$start_port
            increment=-1
        fi

        max_attempts=100 
        attempts=0

        while [ $udp_count -lt $needed_udp_ports ]; do
            if add_port $current_port "udp"; then
                update_port_list
                udp_count=$(echo "$port_list" | grep -c 'udp')
                total_ports=$(echo "$port_list" | grep -c 'udp\|tcp')
            fi

            current_port=$((current_port + increment))
            attempts=$((attempts + 1))

            if [ $attempts -ge $max_attempts ]; then
                echo "超过最大尝试次数，无法添加足够的预留端口"
                exit 1
            fi
        done

        while [ $tcp_count -lt $needed_tcp_ports ]; do
            if add_port $current_port "tcp"; then
                update_port_list
                tcp_count=$(echo "$port_list" | grep -c 'tcp')
                total_ports=$(echo "$port_list" | grep -c 'udp\|tcp')
            fi

            current_port=$((current_port + increment))
            attempts=$((attempts + 1))

            if [ $attempts -ge $max_attempts ]; then
                echo "超过最大尝试次数，无法添加足够的预留端口"
                exit 1
            fi
        done
    done

    local port_list=$(devil port list)

    local TMP_UDP_PORT1=$(echo "$port_list" | grep 'udp' | awk 'NR==1{print $1}')
    local TMP_UDP_PORT2=$(echo "$port_list" | grep 'udp' | awk 'NR==2{print $1}')
    local TMP_UDP_PORT3=$(echo "$port_list" | grep 'udp' | awk 'NR==3{print $1}')
    local TMP_TCP_PORT1=$(echo "$port_list" | grep 'tcp' | awk 'NR==1{print $1}')
    local TMP_TCP_PORT2=$(echo "$port_list" | grep 'tcp' | awk 'NR==2{print $1}')
    local TMP_TCP_PORT3=$(echo "$port_list" | grep 'tcp' | awk 'NR==3{print $1}')

    if [ -n "$TMP_UDP_PORT1" ]; then
        PORT1=$TMP_UDP_PORT1
        if [ -n "$TMP_UDP_PORT2" ]; then
            PORT2=$TMP_UDP_PORT2
            if [ -n "$TMP_UDP_PORT3" ]; then
                PORT3=$TMP_UDP_PORT3
            elif [ -n "$TMP_TCP_PORT1" ]; then
                PORT3=$TMP_TCP_PORT1
            fi
        elif [ -n "$TMP_TCP_PORT1" ]; then
            PORT2=$TMP_TCP_PORT1
            if [ -n "$TMP_TCP_PORT2" ]; then
                PORT3=$TMP_TCP_PORT2
            fi
        fi
    elif [ -n "$TMP_TCP_PORT1" ]; then
        PORT1=$TMP_TCP_PORT1
        if [ -n "$TMP_TCP_PORT2" ]; then
            PORT2=$TMP_TCP_PORT2
            if [ -n "$TMP_TCP_PORT3" ]; then
                PORT3=$TMP_TCP_PORT3
            fi
        fi
    fi
    echo "预留端口为 $PORT1 $PORT2 $PORT3"
}


generate_dotenv() {
    local DOMAIN=$(devil ssl www list | awk '/SNI SSL/{flag=1; next} flag && NF && $6 != "address" {print $8}' | head -n 1)

    generate_uuid() {
    local uuid
    uuid=$(uuidgen -r)
    while [[ ${uuid:0:1} =~ [0-9] ]]; do
        uuid=$(uuidgen -r)
    done
    echo "$uuid"
    }

    printf "请输入你的 Serv00 用户的密码（必填）："
    read -r SERV00PASSWORD
    printf "请输入 ARGO_AUTH（必填）："
    read -r ARGO_AUTH
    printf "请输入 ARGO_DOMAIN（必填）："
    read -r ARGO_DOMAIN
    echo "请在Cloudflare中为隧道添加域名 ${ARGO_DOMAIN} 指向 HTTPS://${DOMAIN}:${PORT3},添加完成请按回车继续"
    read
    printf "请输入 UUID（默认值：de04add9-5c68-8bab-950c-08cd5320df18）："
    read -r UUID
    printf "请输入 WEB_USERNAME（默认值：admin）："
    read -r WEB_USERNAME
    printf "请输入 WEB_PASSWORD（默认值：password）："
    read -r WEB_PASSWORD

    if [ -z "${SERV00PASSWORD}" ]; then
    echo "Error! 密码不能为空！"
    rm -rf ${WORKDIR}/*
    rm -rf ${WORKDIR}/.*
    exit 1
    fi

    if [ -z "${UUID}" ]; then
        echo "正在尝试生成随机 UUID ..."
        UUID=$(generate_uuid)
    fi

    echo "SERV00PASSWORD='${SERV00PASSWORD}'" > ${WORKDIR}/.env
    cat >> ${WORKDIR}/.env << EOF
UUID=${UUID}
WEB_USERNAME=${WEB_USERNAME}
WEB_PASSWORD=${WEB_PASSWORD}
EOF
    if [ -n "${ARGO_AUTH}" ] && [ -n "${ARGO_DOMAIN}" ]; then
    cat >> ${WORKDIR}/.env << EOF
ARGO_AUTH=${ARGO_AUTH}
ARGO_DOMAIN=${ARGO_DOMAIN}
EOF
    fi
}

get_app() {
    echo "正在下载 app.js 请稍候..."
    wget -t 10 -qO ${WORKDIR}/app.js https://raw.githubusercontent.com/k0baya/sb-for-serv00/all-in-one/app.js
    if [ $? -ne 0 ]; then
        echo "app.js 下载失败！请检查网络情况！"
        exit 1
    fi
    echo "正在下载 package.json 请稍候..."
    wget -t 10 -qO ${WORKDIR}/package.json https://raw.githubusercontent.com/k0baya/sb-for-serv00/main/package.json
    if [ $? -ne 0 ]; then
        echo "package.json 下载失败！请检查网络情况！"
        exit 1
    fi
    echo "正在安装依赖，请稍候..."
    nohup npm22 install > /dev/null 2>&1
}

get_core() {
    local TMP_DIRECTORY=$(mktemp -d)
    local FILE="${TMP_DIRECTORY}/sing-box"
    echo "正在下载 sing-box 请稍候..."
    wget -t 10 -qO "$FILE" https://raw.githubusercontent.com/k0baya/sb-for-serv00/main/sing-box
    if [ $? -ne 0 ]; then
        echo "sing-box 安装失败，请检查网络情况"
        exit 1
    fi
    install -m 755 ${TMP_DIRECTORY}/sing-box ${WORKDIR}/sing-box
    rm -rf ${TMP_DIRECTORY}
}

generate_config() {
  cat > ${WORKDIR}/config.json << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [{
      "type": "hysteria2",
      "tag": "hy2-sb",
      "listen": "::",
      "listen_port": ${PORT1},
      "up_mbps": 900,
      "down_mbps": 360,
      "users": [{
        "password": "${UUID}"
      }],
      "ignore_client_bandwidth": false,
      "tls": {
        "enabled": true,
        "alpn": [
          "h3"
        ],
        "certificate_path": "${WORKDIR}/cert.crt",
        "key_path": "${WORKDIR}/private.key"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic5-sb",
      "listen": "::",
      "listen_port": ${PORT2},
      "users": [{
        "uuid": "${UUID}",
        "password": "${UUID}"
      }],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": [
          "h3"
        ],
        "certificate_path": "${WORKDIR}/cert.crt",
        "key_path": "${WORKDIR}/private.key"
      }
    },
    {
	    "type": "vless",
	    "tag": "vl-sb",
	    "listen": "::",
	    "listen_port": ${PORT3},
	    "users": [{
	    	"uuid": "${UUID}"
	    }],
	    "tls": {
	    	"enabled": true,
	    	"alpn": [
	    		"h3"
	    	],
	    	"certificate_path": "${WORKDIR}/cert.crt",
	    	"key_path": "${WORKDIR}/private.key"
	    },
      "multiplex": {
        "enabled": true,
        "padding": false
      },
      "transport": {
        "type": "ws",
        "path": "/serv00-vl",
        "max_early_data": 2560,
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
      }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "domain_strategy": "ipv4_only"
    },
    {
      "type": "wireguard",
      "tag": "wireguard-out",
      "server": "162.159.193.10",
      "server_port": 1701,
      "local_address": [
        "172.16.0.2/32",
        "2606:4700:110:8b82:7e66:1cc9:db92:fbf6/128"
      ],
      "private_key": "kAKpn/A4Rrhi1RvdKuFKurxWh2vYbZPHZQ/HlFFuwGE=",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": [110, 229, 36]
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "ip_version": 6,
        "outbound": "wireguard-out"
      },
      {
        "outbound": "wireguard-out",
        "domain_keyword": [
          "chatgpt",
          "openai",
          "netflix"
        ]
      }
    ]
  }
}
EOF
}

get_certificate() {
    local IP_ADDRESS=$(devil ssl www list | awk '/SNI SSL/{flag=1; next} flag && NF && $6 != "address" {print $6}' | head -n 1)
    local DOMAIN=$(devil ssl www list | awk '/SNI SSL/{flag=1; next} flag && NF && $6 != "address" {print $8}' | head -n 1)

    generate_certificate(){
    local CERT_OUTPUT=$(env SERV00PASSWORD="$SERV00PASSWORD" expect << EOF
spawn devil ssl www get "${IP_ADDRESS}" "${DOMAIN}"
expect "Password:"
send "\$env(SERV00PASSWORD)\r"
expect eof
catch wait result
puts "\nResult: \$result\n"
EOF
)
    local CERTIFICATE=$(echo "$CERT_OUTPUT" | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' ORS='\n')
    local PRIVATE_KEY=$(echo "$CERT_OUTPUT" | awk '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/' ORS='\n')
    if [ -z "${CERTIFICATE}" ] || [ -z "${PRIVATE_KEY}" ]; then
        echo "证书获取失败，请检查是否在面板中成功获取到Let's Encrypt证书"
        exit 1
    fi
    echo "$CERTIFICATE" > ${WORKDIR}/cert.crt
    echo "$PRIVATE_KEY" > ${WORKDIR}/private.key
    }

    [ ! -e ${WORKDIR}/cert.crt ] || [ ! -e ${WORKDIR}/private.key ] && generate_certificate
}

generate_argo() {
    local HOST=$(devil vhost list | awk 'NR>2 {print $2}' | grep '^s')
    local SPAREHOST1=$(devil vhost list | awk 'NR>1 {print $2}' | grep '^c')
    local SPAREHOST2=$(devil vhost list | awk 'NR>1 {print $2}' | grep '^w')
    local DOMAIN=$(devil ssl www list | awk '/SNI SSL/{flag=1; next} flag && NF && $6 != "address" {print $8}' | head -n 1)
	cat > argo.sh << ABC
  #!/usr/bin/bash
  
  USERNAME=\$(whoami)
  USERNAME_DOMAIN=\$(whoami | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
  WORKDIR="/home/\${USERNAME}/domains/\${USERNAME_DOMAIN}.serv00.net/public_nodejs"
  DOMAIN=\$(devil ssl www list | awk '/SNI SSL/{flag=1; next} flag && NF && \$6 != "address" {print \$8}' | head -n 1)
  
  cd \${WORKDIR}
  source \${WORKDIR}/.env
  
  check_file() {
	  wget -t 10 https://cloudflared.bowring.uk/binaries/cloudflared-freebsd-latest.7z
  
	  if [ \$? -ne 0 ]; then
		  echo "Cloudflared 客户端安装失败！请检查 hosts 文件是否屏蔽了下载地址！" > list
		  exit 1
	  else
		  7z x cloudflared-freebsd-latest.7z -bb > /dev/null \
		  && rm cloudflared-freebsd-latest.7z \
		  && mv -f ./temp/* ./cloudflared \
		  && rm -rf temp \
		  && chmod +x cloudflared
	  fi
  }
  
  
  run() {
		  if [[ -n "\${ARGO_AUTH}" && -n "\${ARGO_DOMAIN}" ]]; then
		  if [[ "\$ARGO_AUTH" =~ TunnelSecret ]]; then
			  echo "\$ARGO_AUTH" | sed 's@{@{"@g;s@[,:]@"\0"@g;s@}@"}@g' > \${WORKDIR}/tunnel.json
			  cat > \${WORKDIR}/tunnel.yml << EOF
  tunnel: \$(sed "s@.*TunnelID:\(.*\)}@\1@g" <<< "\$ARGO_AUTH")
  credentials-file: \${WORKDIR}/tunnel.json
  protocol: http2
  
  ingress:
	- hostname: \$ARGO_DOMAIN
	  service: https://\${DOMAIN}:${PORT3}
	  originRequest:
		noTLSVerify: true
	- service: http_status:404
EOF
			  nohup ./cloudflared tunnel --edge-ip-version auto --config tunnel.yml run > /dev/null 2>&1 &
		  elif [[ "\$ARGO_AUTH" =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
			  nohup ./cloudflared tunnel --edge-ip-version auto --protocol http2 run --token \${ARGO_AUTH} > /dev/null 2>&1 &
		  fi
	  else
    nohup ./cloudflared tunnel --edge-ip-version auto --protocol http2 --no-autoupdate --url https://\${DOMAIN}:${PORT3} >/dev/null 2>&1 &
    sleep 5

    attempt_count=0
    max_attempts=10

    while [ -z "\$ARGO_DOMAIN" ] && [ \$attempt_count -lt \$max_attempts ]; do
      LOCALHOST=\$(sockstat -4 -l -P tcp | grep cloudflare | awk '
      {
          for (i=1; i<=NF; i++) {
              if (\$i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+\$/) {
                  print \$i
                  break
              }
          }
      }')
  
      if [ -n "\$LOCALHOST" ]; then
        ARGO_DOMAIN=\$(wget -qO- \$LOCALHOST/quicktunnel | jq -r '.hostname')
      fi
  
      if [ -z "\$ARGO_DOMAIN" ]; then
        sleep 2
        attempt_count=\$((attempt_count + 1))
      fi
    done

    if [ -z "\$ARGO_DOMAIN" ]; then
      echo "警告！当前 IP 创建 Cloudflare 临时隧道数量已超出每小时限制，请删除 ~/xray，并等待一小时后重试。或者尝试固定 Argo 隧道使用本仓库。" > list
      echo "Warning! The number of Cloudflare temporary tunnels created by the current IP has exceeded the hourly limit, please remove ~/xray and wait one hour before retrying." >> list
      rm -rf \${WORKDIR}/.*
      rm -rf \${WORKDIR}/*
    fi
  fi
	  }
  
    export_list() {
        cat > ${WORKDIR}/list << EOF
*******************************************
        
hy2配置：
        
hysteria2://${UUID}@${HOST}:${PORT1}/?sni=${DOMAIN}#PL-hy2-k0baya-serv00
        
----------------------------
        
tuic5配置：
        
tuic://${UUID}:${UUID}@${HOST}:${PORT2}//?congestion_control=bbr&udp_relay_mode=native&sni=${DOMAIN}&alpn=h3#PL-tuic5-k0baya-serv00
        
----------------------------
        
vless配置：
        
vless://${UUID}@${HOST}:${PORT3}?alpn=h3&flow=&host=${DOMAIN}&path=/serv00-vl&security=tls&sni=${DOMAIN}&type=ws#PL-Vless-k0baya-serv00s
        
----------------------------
        
vless配置：
        
vless://${UUID}@${SPAREHOST1}:${PORT3}?alpn=h3&flow=&host=${DOMAIN}&path=/serv00-vl&security=tls&sni=${DOMAIN}&type=ws#PL-Vless-k0baya-serv00c

----------------------------
        
vless配置：
        
vless://${UUID}@${SPAREHOST2}:${PORT3}?alpn=h3&flow=&host=${DOMAIN}&path=/serv00-vl&security=tls&sni=${DOMAIN}&type=ws#PL-Vless-k0baya-serv00w

----------------------------
        
vless配置：
        
vless://${UUID}@upos-sz-mirrorcf1ov.bilivideo.com:443?alpn=h3&flow=&host=\${ARGO_DOMAIN}&path=/serv00-vl&security=tls&sni=\${ARGO_DOMAIN}&type=ws#PL-Argo-Vless-k0baya-serv00

*******************************************
EOF

echo \$(echo -n "hysteria2://${UUID}@${HOST}:${PORT1}/?sni=${DOMAIN}#PL-hy2-k0baya-serv00

tuic://${UUID}:${UUID}@${HOST}:${PORT2}//?congestion_control=bbr&udp_relay_mode=native&sni=${DOMAIN}&alpn=h3#PL-tuic5-k0baya-serv00

vless://${UUID}@${HOST}:${PORT3}?alpn=h3&flow=&host=${DOMAIN}&path=/serv00-vl&security=tls&sni=${DOMAIN}&type=ws#PL-Vless-k0baya-serv00

vless://${UUID}@${SPAREHOST1}:${PORT3}?alpn=h3&flow=&host=${DOMAIN}&path=/serv00-vl&security=tls&sni=${DOMAIN}&type=ws#PL-Vless-k0baya-serv00

vless://${UUID}@${SPAREHOST2}:${PORT3}?alpn=h3&flow=&host=${DOMAIN}&path=/serv00-vl&security=tls&sni=${DOMAIN}&type=ws#PL-Vless-k0baya-serv00

vless://${UUID}@upos-sz-mirrorcf1ov.bilivideo.com:443?alpn=h3&flow=&host=\${ARGO_DOMAIN}&path=/serv00-vl&security=tls&sni=\${ARGO_DOMAIN}&type=ws#PL-Argo-Vless-k0baya-serv00" | base64 ) > ${WORKDIR}/sub
  }

[ ! -e \${WORKDIR}/cloudflared ] && check_file
run
export_list
ABC
}

set_language
set_domain_dir
reserve_port

cd ${WORKDIR}

[ ! -e ${WORKDIR}/.env ] && generate_dotenv
echo "正在检查所需文件..."
[ -e ${WORKDIR}/.env ] && source ${WORKDIR}/.env
[ ! -e ${WORKDIR}/app.js ] || [ ! -e ${WORKDIR}/package.json ] && get_app
[ ! -e ${WORKDIR}/sing-box ] && get_core
[ ! -e ${WORKDIR}/argo.sh ] && generate_argo
echo "正在尝试生成配置..."
[ ! -e ${WORKDIR}/cert.crt ] || [ ! -e ${WORKDIR}/private.key ] && get_certificate
generate_config
[ -e ${WORKDIR}/cert.crt ] && [ -e ${WORKDIR}/private.key ] && echo "请访问 https://${USERNAME_DOMAIN}.serv00.net/status 获取服务端状态, 当 sing-box 和 cloudflared 正常运行后，访问 https://${USERNAME_DOMAIN}.serv00.net/list 获取配置" && exit 0

echo "Error: 证书获取失败！请检查密码填写是否正确！"
