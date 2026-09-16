#!/bin/bash

# Цвета для вывода
GRN='\033[1;32m'
RED='\033[1;31m'
YEL='\033[1;33m'
NC='\033[0m' # No Color

[[ $EUID -eq 0 ]] || {
    echo -e "${RED}❌ скрипту нужны root права ${NC}"
    exit 1
}

DOMAIN=$1

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}❌ Ошибка: домен не задан.${NC}"
    exit 1
fi

echo -e "${YEL}Обновление и установка необходимых пакетов...${NC}"
apt-get update && apt-get install curl jq dnsutils openssl nginx certbot netcat-openbsd -y
systemctl enable --now nginx

LOCAL_IP=$(hostname -I | awk '{print $1}')
DNS_IP=$(dig +short "$DOMAIN" | grep '^[0-9]' | head -n 1)

if [ "$LOCAL_IP" != "$DNS_IP" ]; then
    echo -e "${RED}❌ Внимание: IP-адрес ($LOCAL_IP) не совпадает с A-записью $DOMAIN ($DNS_IP).${NC}"
    echo -e "${YEL}Правильно укажите одну A-запись для вашего домена в ДНС - $LOCAL_IP ${NC}"
    read -p "Продолжить на ваш страх и риск? (y/N):" choice

    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Выполнение скрипта прервано.${NC}"
        exit 1
    fi
    echo -e "${YEL}Продолжение выполнения скрипта...${NC}"
fi

# === ВОПРОСЫ ПОЛЬЗОВАТЕЛЮ ===
read -p "$(echo -e "\n${YEL}Устанавливать WARP для обхода блокировок некоторых сайтов? (y/n, по умолчанию n): ${NC}")" choice_warp
choice_warp=${choice_warp:-n}
if [[ "$choice_warp" =~ ^[Yy]$ ]]; then
    TAG_WARP="warp"
    INSTALL_WARP=true
else
    TAG_WARP="direct"
    INSTALL_WARP=false
fi

# Включаем BBR
bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
if [ "$bbr" = "bbr" ]; then
    echo -e "${GRN}BBR уже запущен${NC}"
else
    echo "net.core.default_qdisc=fq" > /etc/sysctl.d/999-autoXRAY.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/999-autoXRAY.conf
    sysctl --system
    echo -e "${GRN}BBR активирован${NC}"
fi


cat <<EOF > /etc/security/limits.d/99-autoXRAY.conf
*       soft    nofile  1048576
*       hard    nofile  1048576
root    soft    nofile  1048576
root    hard    nofile  1048576
EOF
ulimit -n 65535
echo -e "${GRN}Лимиты применены. Текущий ulimit -n: $(ulimit -n) ${NC}"


# Создание директории сайта
WEB_PATH="/var/www/$DOMAIN"
mkdir -p "$WEB_PATH"

# Генерируем сайт маскировку
bash -c "$(curl -sL https://github.com/v0vc/autoXRAY/raw/refs/heads/main/test/gen_page3.sh)" -- "$WEB_PATH"

# Установка Xray
bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version v26.9.9

# Блок CERTBOT - START

# Определяем путь к конфигу nginx
if [ -f /etc/nginx/sites-available/default ]; then
    CONFIG_PATH="/etc/nginx/sites-available/default"
	echo -e "${GRN}Обнаружена стандартная сборка nginx. ${NC}"
elif [ -f /etc/nginx/conf.d/default.conf ]; then
    CONFIG_PATH="/etc/nginx/conf.d/default.conf"
	echo -e "${YEL}Обнаружена нестандартная сборка nginx. Предварительная настройка NGINX для CERTBOT ${NC}"
	mkdir -p /var/www/html

# Записываем временный конфиг
cat <<EOF > "$CONFIG_PATH"
server {
	listen 80 default_server;
	server_name _;

	location /.well-known/acme-challenge/ {
		root /var/www/html;
		allow all;
	}

	location / {
		return 301 https://\$host\$request_uri;
	}
}
EOF
	systemctl reload nginx
else
    echo -e "${RED}Не найден ни один default конфиг nginx${NC}"
    exit 1
fi


mkdir -p /var/lib/xray/cert/

if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /var/lib/xray/cert/fullchain.pem
    cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /var/lib/xray/cert/privkey.pem
    chmod 744 /var/lib/xray/cert/privkey.pem
    chmod 744 /var/lib/xray/cert/fullchain.pem
fi

certbot certonly --webroot -w /var/www/html \
  -d $DOMAIN \
  -m mail@$DOMAIN \
  --agree-tos --non-interactive \
  --deploy-hook "systemctl reload nginx; cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /var/lib/xray/cert/fullchain.pem; cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /var/lib/xray/cert/privkey.pem; chmod 744 /var/lib/xray/cert/privkey.pem; chmod 744 /var/lib/xray/cert/fullchain.pem; systemctl restart xray"

RET=$?

if [ $RET -eq 0 ]; then
  echo -e "\n${GRN}========================================"
  echo    "✅  Команда certbot успешно выполнена"
  echo    "✅  Сертификат https от letsencrypt ПОЛУЧЕН"
  echo    "========================================"
  echo -e "${NC}"
else
  echo -e "\n${RED}========================================"
  echo    "❌  CERTBOT ЗАВЕРШИЛСЯ С ОШИБКОЙ"
  echo    "❌  Сертификат https от letsencrypt НЕ ПОЛУЧЕН!"
  echo    "❌  Смотрите выше логи процесса получения сертификата"
  echo    "❌  Код возврата: $RET"
  echo    "========================================"
  echo -e "${NC}"
  exit 1
fi
# Блок CERTBOT - END

# конфиг nginx

path_xhttp=$(openssl rand -base64 15 | tr -dc 'a-z0-9' | head -c 6)
path_subpage=$(openssl rand -base64 15 | tr -dc 'A-Za-z0-9' | head -c 20)

# Выбираем один сценарий ошибки
AUTH_VARIANTS=(
    "ERR_INVALID_CREDENTIALS|The username or password you entered is incorrect."
    "ERR_INVALID_CREDENTIALS|The identity or security key you provided is invalid."
    "ERR_BAD_PASSWORD|Incorrect password. Please verify your credentials and retry."
    "ERR_KEY_MISMATCH|The security key provided does not match the account identity."
    "ERR_CREDENTIAL_REJECTED|Credential verification rejected by the authentication authority."
    "ERR_PASSWORD_MISMATCH|The password provided does not match the registered key."
    "ERR_INCORRECT_KEY|Incorrect security credentials provided for this principal."
    "ERR_USER_NOT_FOUND|Principal identity not found in directory services."
    "ERR_IDENTITY_NOT_FOUND|No account found matching the provided identity."
    "ERR_PRINCIPAL_MISSING|User principal does not exist in this organizational realm."
    "ERR_ACCOUNT_NOT_FOUND|Account identifier not recognized by the identity provider."
    "ERR_UNKNOWN_USER|Unrecognized user identity. Please verify your login."
    "ERR_LOOKUP_FAILED|User lookup failed: Specified identity does not exist."
    "ERR_AUTH_FAILED|Authentication failed: The provided credentials do not match."
    "ERR_DIRECTORY_MISMATCH|Credentials could not be verified against the corporate directory."
    "ERR_RECORDS_MISMATCH|The security credentials entered do not match our records."
)

RAND_AUTH=${AUTH_VARIANTS[$RANDOM % ${#AUTH_VARIANTS[@]}]}
AUTH_CODE=$(echo "$RAND_AUTH" | cut -d'|' -f1)
AUTH_MSG=$(echo "$RAND_AUTH" | cut -d'|' -f2)

# Конфиг Nginx
cat <<EOF > "$CONFIG_PATH"
server {
    server_name $DOMAIN;
    listen 443 ssl http2;
    server_tokens off;

    root /var/www/$DOMAIN;
    index index.html;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m;
    ssl_session_tickets off;

    ssl_certificate "/etc/letsencrypt/live/$DOMAIN/fullchain.pem";
    ssl_certificate_key "/etc/letsencrypt/live/$DOMAIN/privkey.pem";

    location = /${path_subpage}.json {
        add_header profile-title "base64:YXV0b1hSQVk=";
        add_header routing "happ://routing/onadd/eyJOYW1lIjoiYXV0b1hSQVkiLCJHbG9iYWxQcm94eSI6InRydWUiLCJSb3V0ZU9yZGVyIjoiYmxvY2stcHJveHktZGlyZWN0IiwiUmVtb3RlRE5TVHlwZSI6IkRvSCIsIlJlbW90ZUROU0RvbWFpbiI6Imh0dHBzOi8vZG5zLmdvb2dsZS9kbnMtcXVlcnkiLCJSZW1vdGVETlNJUCI6IjguOC40LjQiLCJEb21lc3RpY0ROU1R5cGUiOiJEb0giLCJEb21lc3RpY0ROU0RvbWFpbiI6Imh0dHBzOi8vY2xvdWRmbGFyZS1kbnMuY29tL2Rucy1xdWVyeSIsIkRvbWVzdGljRE5TSVAiOiIxLjEuMS4xIiwiR2VvaXB1cmwiOiJodHRwczovL2dpdGh1Yi5jb20vTG95YWxzb2xkaWVyL3YycmF5LXJ1bGVzLWRhdC9yZWxlYXNlcy9sYXRlc3QvZG93bmxvYWQvZ2VvaXAuZGF0IiwiR2Vvc2l0ZXVybCI6Imh0dHBzOi8vZ2l0aHViLmNvbS9Mb3lhbHNvbGRpZXIvdjJyYXktcnVsZXMtZGF0L3JlbGVhc2VzL2xhdGVzdC9kb3dubG9hZC9nZW9zaXRlLmRhdCIsIkxhc3RVcGRhdGVkIjoiMTc3NTIwNjEwOCIsIkRuc0hvc3RzIjp7fSwiRGlyZWN0U2l0ZXMiOlsiZ2Vvc2l0ZTpjYXRlZ29yeS1ydSIsImdlb3NpdGU6cHJpdmF0ZSJdLCJEaXJlY3RJcCI6WyJnZW9pcDpwcml2YXRlIl0sIlByb3h5U2l0ZXMiOltdLCJQcm94eUlwIjpbXSwiQmxvY2tTaXRlcyI6WyJnZW9zaXRlOmNhdGVnb3J5LWFkcyIsImdlb3NpdGU6d2luLXNweSJdLCJCbG9ja0lwIjpbXSwiRG9tYWluU3RyYXRlZ3kiOiJJUElmTm9uTWF0Y2giLCJGYWtlRE5TIjoiZmFsc2UiLCJVc2VDaHVua0ZpbGVzIjoiZmFsc2UifQ";
        add_header routing-enable 0;
    }

    # Для сайта
    location /api/v1/authenticate {
        limit_except POST {
            deny all;
        }
        default_type application/json;
        add_header Set-Cookie "X-Auth-Token=\$request_id; Path=/; HttpOnly; Secure; SameSite=Lax" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Cache-Control "no-store, no-cache, must-revalidate" always;
        return 401 '{"success":false,"code":"$AUTH_CODE","message":"$AUTH_MSG","request_id":"\$request_id"}';
    }

    location ~ /\.ht {
        deny all;
    }
}

server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

systemctl restart nginx
echo -e "${GRN}✅ Конфигурация nginx обновлена.${NC}"

SCRIPT_DIR=/usr/local/etc/xray

# Генерируем переменные
hysteria_tag="Hysteria2"
xray_shortIds_vrv=$(openssl rand -hex 8)

# Установка WARP-cli
if [ "$INSTALL_WARP" = true ]; then
    if ss -tuln | grep -q ":40000 "; then
        echo -e "${GRN}WARP-cli (Socks5 на порту 40000) уже работает. Пропускаем.${NC}"
    else
        echo -e "${GRN}Установка WARP-cli (автоматически)...${NC}"
        echo -e "1\n1\n40000" | bash <(curl -fsSL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) w
    fi
else
    echo -e "${YEL}Установка WARP пропущена по выбору пользователя.${NC}"
fi

# Экспортируем переменные для envsubst
export xray_shortIds_vrv DOMAIN path_subpage path_xhttp WEB_PATH hysteria_tag

# Создаем JSON конфигурацию сервера
cat <<'EOF' | envsubst >"$SCRIPT_DIR/config.json"
{
    "log": {
        "dnsLog": false,
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log",
        "loglevel": "none"
    },
    "dns": {
        "servers": [
            "https+local://8.8.4.4/dns-query",
            "https+local://8.8.8.8/dns-query",
            "https+local://1.1.1.1/dns-query",
            "localhost"
        ],
        "queryStrategy": "UseIPv4"
    },
    "inbounds": [
        {
            "tag": "${hysteria_tag}",
            "listen": "0.0.0.0",
            "port": 8080,
            "protocol": "hysteria",
            "settings": {
                "version": 2,
                "clients": [
                    {
                        "auth": "${xray_shortIds_vrv}"
                    }
                ]
            },
            "streamSettings": {
                "network": "hysteria",
                "security": "tls",
                "tlsSettings": {
                    "serverName": "$DOMAIN",
                    "alpn": [
                        "h3"
                    ],
                    "certificates": [
                        {
                            "usage": "encipherment",
                            "certificateFile": "/var/lib/xray/cert/fullchain.pem",
                            "keyFile": "/var/lib/xray/cert/privkey.pem"
                        }
                    ]
                },
                "hysteriaSettings": {
                    "version": 2,
                    "auth": "${xray_shortIds_vrv}"
                },
                "finalmask": {
                    "quicParams": {
                        "congestion": "bbr",
                        "brutalUp": "30 mbps",
                        "brutalDown": "100 mbps"
                    }
                }
            }
        }
    ],
    "outbounds": [
        {
            "tag": "direct",
            "protocol": "freedom",
            "streamSettings": {
                "sockopt": {
                    "domainStrategy": "ForceIPv4"
                }
            }
        },
        {
            "tag": "block",
            "protocol": "blackhole"
        },
        {
            "tag": "warp",
            "protocol": "socks",
            "settings": {
                "servers": [
                    {
                        "address": "127.0.0.1",
                        "port": 40000
                    }
                ]
            },
            "targetStrategy": "ForceIPv4v6"
        }
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "ip": [
                    "geoip:private"
                ],
                "outboundTag": "block"
            },
            {
                "port": "25,135,137-139,445",
                "outboundTag": "block"
            },
            {
                "protocol": [
                    "bittorrent"
                ],
                "outboundTag": "block"
            },
            {
                "domain": [
                    "geosite:category-ads",
                    "geosite:win-spy",
                    "geosite:private"
                ],
                "outboundTag": "block"
            },
            {
                "outboundTag": "warp",
                "domain": [
                    "4pda.to",
                    "habr.com",
                    "adobe.io",
                    "jetbrains.ai",
                    "terraform.io",
                    "istio.io",
                    "karavel.store",
                    "geosite:category-ip-geo-detect",
                    "geosite:google-gemini",
                    "geosite:canva",
                    "geosite:openai",
                    "geosite:whatsapp",
                    "geosite:twitter",
                    "geosite:meta",
                    "geosite:telegram",
                    "geosite:ru-blocked"
                ]
            }
        ]
    }
}

EOF

# Создаем JSON конфигурацию клиента
print_config() {
    local PROXY_OUTBOUND="$1"
    local REMARK="$2"

    cat <<TPL
{
    "log": {
        "loglevel": "warning"
    },
    "dns": {
        "servers": [
            {
                "address": "https+local://77.88.8.8/dns-query",
                "domains": [
                    "geosite:category-ru",
                    "geosite:yandex",
                    "geosite:vk",
                    "domain:ru",
                    "domain:su",
                    "domain:xn--p1ai"
                ],
                "skipFallback": true
            },
            "https://8.8.4.4/dns-query",
            "https://8.8.8.8/dns-query",
            "https://1.1.1.1/dns-query"
        ],
        "queryStrategy": "UseIPv4"
    },
    "routing": {
        "domainMatcher": "hybrid",
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "protocol": [
                    "bittorrent"
                ],
                "outboundTag": "direct"
            },
            {
                "ip": [
                    "geoip:private",
                    "geoip:ru"
                ],
                "outboundTag": "direct"
            },
            {
                "domain": [
                    "geosite:category-ads-all",
                    "geosite:win-spy"
                ],
                "outboundTag": "block"
            },
            {
                "ip": [
                    "geoip:ru-blocked"
                ],
                "outboundTag": "proxy"
            },
            {
                "domain": [
                    "geosite:ru-blocked"
                ],
                "outboundTag": "proxy"
            },
            {
                "domain": [
                    "domain:ru",
                    "domain:su",
                    "domain:xn--p1ai",
                    "geosite:private",
                    "geosite:apple",
                    "geosite:apple-pki",
                    "geosite:category-android-app-download",
                    "geosite:f-droid",
                    "geosite:yandex",
                    "geosite:vk",
                    "geosite:microsoft",
                    "geosite:win-update",
                    "geosite:win-extra",
                    "geosite:google-play",
                    "geosite:steam",
                    "geosite:twitch",
                    "geosite:category-ru",
                    "geosite:youtube"
                ],
                "outboundTag": "direct"
            }
        ]
    },
    "inbounds": [
        {
            "tag": "socks-in",
            "protocol": "socks",
            "listen": "127.0.0.1",
            "port": 10808,
            "settings": {
                "udp": true
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            }
        }
    ],
    "outbounds": [
        $PROXY_OUTBOUND,
        {
            "tag": "direct",
            "protocol": "freedom"
        },
        {
            "tag": "block",
            "protocol": "blackhole"
        }
    ],
    "remarks": "$REMARK"
}
TPL
}

# --- Config 1
HYSTERIA2='{
    "tag": "proxy",
    "protocol": "hysteria",
    "settings": {
        "address": "$DOMAIN",
        "port": 8080,
        "version": 2
    },
    "streamSettings": {
        "network": "hysteria",
        "security": "tls",
        "tlsSettings": {
            "serverName": "$DOMAIN",
            "alpn": [
                "h3"
            ]
        },
        "hysteriaSettings": {
            "version": 2,
            "auth": "${xray_shortIds_vrv}"
        },
        "finalmask": {
            "quicParams": {
                "congestion": "bbr",
                "brutalUp": "30 mbps",
                "brutalDown": "100 mbps"
            }
        }
    }
}'

(
    echo "["
    print_config "$HYSTERIA2" "🇪🇺 HYSTERIA2"
    echo "]"
) | envsubst >"$WEB_PATH/$path_subpage.json"

echo -e "Обновляем ru geosite/geoip"
bash -c "$(curl -L https://github.com/zolg/Xray-install/raw/main/install-release.sh)" @ install-geodata

systemctl restart xray
echo -e "Перезапуск XRAY"

# Формирование ссылок
subPageLink="https://$DOMAIN/$path_subpage.json"

# Формирование ссылок
hy2="hy2://${xray_shortIds_vrv}@$DOMAIN:8080/?sni=$DOMAIN&alpn=h3#${hysteria_tag}"

configListLink="https://$DOMAIN/$path_subpage.html"

CONFIGS_ARRAY=(
    "HYSTERIA2|$hy2"
)
ALL_LINKS_TEXT=""

# --- ЗАПИСЬ HEAD (СТАТИКА, МИНИФИЦИРОВАННЫЕ СТИЛИ И JS) ---
cat >"$WEB_PATH/$path_subpage.html" <<'EOF'
<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<meta name="robots" content="noindex,nofollow">
<title>autoXRAY configs</title>
<link rel="icon" type="image/svg+xml" href='data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjMDBCRkZGIiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBhdGggZD0iTTIxIDJsLTIgMm0tNy42MSA3LjYxYTUuNSA1LjUgMCAxIDEtNy43NzggNy43NzggNS41IDUuNSAwIDAgMSA3Ljc3Ny03Ljc3N3ptMCAwTDE1LjUgNy41bTAgMGwzIDNMMjIgN2wtMy0zbS0zLjUgMy41TDE5IDQiLz48L3N2Zz4='>
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<style>
body{font-family:monospace;background:#121212;color:#e0e0e0;padding:10px;max-width:900px;margin:0 auto}h2{color:#c3e88d;border-top:2px solid #333;padding-top:20px;margin:15px 0 10px;font-size:18px}.config-row{background:#1e1e1e;border:1px solid #333;border-radius:6px;padding:5px;display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-bottom:8px}.config-label{background:#2c2c2c;color:#82aaff;padding:6px 10px;border-radius:4px;font-weight:700;font-size:13px;white-space:nowrap;min-width:140px;text-align:center}.config-code{flex:1;white-space:nowrap;overflow-x:auto;padding:8px;background:#121212;border-radius:4px;color:#c3e88d;font-size:12px;scrollbar-width:none}.config-code::-webkit-scrollbar{display:none}.btn-action{border:1px solid #555;padding:6px 12px;border-radius:4px;cursor:pointer;font-weight:700;font-size:12px;transition:all .2s;height:32px;display:flex;align-items:center;justify-content:center}.copy-btn{background:#333;color:#e0e0e0;min-width:60px}.copy-btn:hover{background:#c3e88d;color:#121212;border-color:#c3e88d}.qr-btn{background:#333;color:#82aaff;border-color:#82aaff;min-width:40px}.qr-btn:hover{background:#82aaff;color:#121212}.btn-group{display:flex;gap:10px;margin:10px 0 20px}.btn{flex:1;background:#2c2c2c;color:#c3e88d;border:1px solid #c3e88d;padding:10px;text-align:center;border-radius:6px;text-decoration:none;font-weight:700;font-size:14px}.btn:hover{background:#c3e88d;color:#121212}.btn.download{border-color:#82aaff;color:#82aaff}.btn.download:hover{background:#82aaff;color:#121212}.btn.tg{border-color:#2AABEE;color:#2AABEE}.btn.tg:hover{background:#2AABEE;color:#fff}.modal-overlay{display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.85);z-index:999;justify-content:center;align-items:center;backdrop-filter:blur(3px)}.modal-content{background:#1e1e1e;padding:20px;border-radius:10px;border:1px solid #82aaff;text-align:center}#qrcode{background:#fff;padding:10px;border-radius:6px;margin-bottom:10px}.close-modal-btn{background:#c31e1e;color:#fff;border:none;padding:8px 20px;border-radius:4px;cursor:pointer}@media(max-width:600px){.config-label{width:100%;margin-bottom:2px}.config-code{min-width:100%;order:3}.btn-action{flex:1;order:2}}
</style>
<script>
function copyText(e,t){navigator.clipboard.writeText(document.getElementById(e).innerText).then(()=>{let o=t.innerText;t.innerText="OK",t.style.cssText="background:#c3e88d;color:#121212",setTimeout(()=>{t.innerText=o,t.style.cssText=""},1500)}).catch(e=>console.error(e))}function showQR(e){let t=document.getElementById(e).innerText,o=document.getElementById("qrModal"),n=document.getElementById("qrcode");n.innerHTML="",new QRCode(n,{text:t,width:256,height:256,colorDark:"#000000",colorLight:"#ffffff",correctLevel:QRCode.CorrectLevel.L}),o.style.display="flex"}function closeModal(){document.getElementById("qrModal").style.display="none"}window.onclick=function(e){e.target==document.getElementById("qrModal")&&closeModal()};
</script>
</head><body>
EOF

# --- ЗАПИСЬ BODY (ДИНАМИЧЕСКИЕ ДАННЫЕ) ---
cat >>"$WEB_PATH/$path_subpage.html" <<EOF

<h2>📂 Ссылка на подписку (готовый конфиг клиента с роутингом)</h2>
<div class="config-row">
    <div class="config-label">Subscription</div>
    <div class="config-code" id="subLink">$subPageLink</div>
    <button class="btn-action copy-btn" onclick="copyText('subLink', this)">Copy</button>
    <button class="btn-action qr-btn" onclick="showQR('subLink')">QR</button>
</div>

EOF

# Цикл генерации строк конфигов
idx=1
for item in "${CONFIGS_ARRAY[@]}"; do
    title="${item%%|*}"
    link="${item#*|}"
    if [ -z "$ALL_LINKS_TEXT" ]; then ALL_LINKS_TEXT="$link"; else ALL_LINKS_TEXT="$ALL_LINKS_TEXT<br>$link"; fi
    cat >>"$WEB_PATH/$path_subpage.html" <<EOF
<div class="config-row">
    <div class="config-label">$title</div>
    <div class="config-code" id="c$idx">$link</div>
    <button class="btn-action copy-btn" onclick="copyText('c$idx', this)">Copy</button>
    <button class="btn-action qr-btn" onclick="showQR('c$idx')">QR</button>
</div>
EOF
    ((idx++))
done

# Дописываем All links и подвал
cat >>"$WEB_PATH/$path_subpage.html" <<EOF
<div id="qrModal" class="modal-overlay"><div class="modal-content"><div id="qrcode"></div><button class="close-modal-btn" onclick="closeModal()">Close</button></div></div>
</body></html>
EOF

# --- ФИНАЛЬНАЯ ПРОВЕРКА ---
echo -e "\n${YEL}=== Финальная проверка статусов ===${NC}"

# Проверка WARP-cli (Socks5 порт 40000)
if [ "$INSTALL_WARP" = true ]; then
    if ss -nlt | grep -q ":40000\b"; then
        echo -e "WARP-cli: ${GRN}LISTENING${NC}"
    else
        echo -e "WARP-cli: ${RED}NOT LISTENING${NC}"
    fi
fi

# Проверка Nginx
if systemctl is-active --quiet nginx; then
    echo -e "Nginx: ${GRN}RUNNING${NC}"
else
    echo -e "Nginx: ${RED}STOPPED/ERROR${NC}"
fi

# Проверка XRAY
if systemctl is-active --quiet xray; then
    echo -e "XRAY: ${GRN}RUNNING${NC}"
else
    echo -e "XRAY: ${RED}STOPPED/ERROR${NC}"
fi

echo -e "

${YEL}HYSTERIA2 ${NC}
$hy2

${YEL}Ваша json страничка подписки ${NC}
$subPageLink

${YEL}Ссылка на сохраненные конфиги ${NC}
${GRN}$configListLink ${NC}

"
