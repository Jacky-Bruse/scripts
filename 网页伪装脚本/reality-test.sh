#!/usr/bin/env bash
# 在 VPS 上用 Xray 客户端连接本机的 REALITY 入站，绕开防火墙检测配置是否正确
# 用法：bash reality-test.sh 40989
PORT="${1:-443}"
XRAY=$(ls /usr/local/x-ui/bin/xray-linux-* 2>/dev/null | head -1)
CFG=/usr/local/x-ui/bin/config.json
TMP=/root/reality-test; mkdir -p "$TMP"

read -r PRIV UUID FLOW SNI SID < <(python3 - "$PORT" "$CFG" <<'P'
import json, sys
port, cfg = int(sys.argv[1]), json.load(open(sys.argv[2]))
for ib in cfg.get("inbounds", []):
    ss = ib.get("streamSettings", {})
    if ib.get("port") == port and ss.get("security") == "reality":
        r = ss["realitySettings"]; cl = ib["settings"]["clients"][0]
        print(r["privateKey"], cl["id"], cl.get("flow") or "-", r["serverNames"][0], (r.get("shortIds") or [""])[0])
        break
P
)
[[ -n "$PRIV" ]] || { echo "没找到端口 $PORT 上的 REALITY 入站"; exit 1; }
[[ "$FLOW" == "-" ]] && FLOW=""
PUB=$("$XRAY" x25519 -i "$PRIV" | awk -F': *' '/Password|Public/{print $2; exit}')

echo "== 服务端实际参数（拿去和手机客户端逐项对比）=="
echo "端口: $PORT"; echo "SNI: $SNI"; echo "公钥(pbk): $PUB"; echo "shortId: $SID"; echo "flow: ${FLOW:-无}"
echo "UUID 前8位: ${UUID:0:8}..."

cat > "$TMP/client.json" <<J
{
  "log": {"loglevel": "debug"},
  "inbounds": [{"listen": "127.0.0.1", "port": 10808, "protocol": "socks"}],
  "outbounds": [{
    "protocol": "vless",
    "settings": {"vnext": [{"address": "127.0.0.1", "port": $PORT,
      "users": [{"id": "$UUID", "encryption": "none", "flow": "$FLOW"}]}]},
    "streamSettings": {"network": "tcp", "security": "reality",
      "realitySettings": {"serverName": "$SNI", "fingerprint": "chrome",
        "password": "$PUB", "publicKey": "$PUB", "shortId": "$SID"}}
  }]
}
J

echo; echo "== 伪装站经 $PORT 端口是否正常 =="
echo | openssl s_client -connect 127.0.0.1:"$PORT" -servername "$SNI" -tls1_3 2>/dev/null | grep -aE "subject=|issuer=|Protocol" || echo "握手失败"

echo; echo "== 本机代理连接测试 =="
"$XRAY" run -c "$TMP/client.json" > "$TMP/client.log" 2>&1 &
XPID=$!; sleep 3
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -x socks5h://127.0.0.1:10808 https://www.google.com/generate_204)
kill $XPID 2>/dev/null
if [[ "$CODE" == "204" ]]; then
  echo "✔ 代理连接成功：服务端配置正确"
else
  echo "✘ 代理连接失败（返回: ${CODE:-无}），客户端日志："
  grep -aiE "reality|error|fail|warn" "$TMP/client.log" | tail -15
fi

echo; echo "== 防火墙 =="
command -v ufw >/dev/null && ufw status | head -15
iptables -S INPUT 2>/dev/null | head -10
