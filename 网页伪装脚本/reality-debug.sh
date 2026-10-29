#!/usr/bin/env bash
# 复制 3x-ui 里指定端口的 REALITY 入站，单独起一个带完整调试日志的 Xray 服务端（端口 40999，只监听本机），
# 再用客户端连它，把服务端和客户端两边的日志都打印出来。不改动 3x-ui 的任何配置。
# 先运行过 reality-test.sh（需要它生成的 client.json）。用法：bash reality-debug.sh 40989
SRC_PORT="${1:-443}"; DBG_PORT=40999
XRAY=$(ls /usr/local/x-ui/bin/xray-linux-* 2>/dev/null | head -1)
CFG=/usr/local/x-ui/bin/config.json
TMP=/root/reality-test
[[ -f "$TMP/client.json" ]] || { echo "请先运行 bash reality-test.sh $SRC_PORT"; exit 1; }

python3 - "$SRC_PORT" "$DBG_PORT" "$CFG" "$TMP" <<'P' || exit 1
import json, sys, copy
src, dbg, cfgp, tmp = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], sys.argv[4]
c = json.load(open(cfgp))
ib = next((i for i in c.get("inbounds", []) if i.get("port") == src), None)
if not ib:
    sys.exit(f"没找到端口 {src} 的入站")
ib = copy.deepcopy(ib)
ib.update({"port": dbg, "listen": "127.0.0.1", "tag": "debug-in"})
ib["streamSettings"]["realitySettings"]["show"] = True
srv = {"log": {"loglevel": "debug"}, "inbounds": [ib], "outbounds": [{"protocol": "freedom"}]}
json.dump(srv, open(f"{tmp}/server.json", "w"), indent=1)
cl = json.load(open(f"{tmp}/client.json"))
cl["outbounds"][0]["settings"]["vnext"][0]["port"] = dbg
json.dump(cl, open(f"{tmp}/client-dbg.json", "w"), indent=1)
P

"$XRAY" run -c "$TMP/server.json" > "$TMP/server.log" 2>&1 & SPID=$!
sleep 2
"$XRAY" run -c "$TMP/client-dbg.json" > "$TMP/client-dbg.log" 2>&1 & CPID=$!
sleep 2
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -x socks5h://127.0.0.1:10808 https://www.google.com/generate_204)
sleep 1; kill $CPID $SPID 2>/dev/null; wait 2>/dev/null

echo "== 结果: $( [[ $CODE == 204 ]] && echo '✔ 成功' || echo "✘ 失败 (返回 ${CODE:-无})" ) =="
echo; echo "== 服务端日志 =="
grep -avE "^\s*$" "$TMP/server.log" | tail -40
echo; echo "== 客户端日志 =="
grep -aiE "reality|error|fail|warn" "$TMP/client-dbg.log" | tail -15
