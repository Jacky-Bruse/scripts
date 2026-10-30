# REALITY "偷自己" 部署说明

用自己的域名和自己服务器上的小网站给 REALITY 做伪装（Target 指向本机网站），配合 3x-ui 使用。

## 原理

```
                      ┌──────────────── VPS ────────────────┐
客户端 / 访客 / 探测  │                                      │
  ──► 你的域名:443 ──►│ Xray (3x-ui, 公网 443)               │
                      │   ├─ 带 REALITY 密钥 → 正常代理      │
                      │   └─ 不带密钥 → 转给 127.0.0.1:8443  │
                      │                    │                 │
                      │           Nginx 网站（只监听本机）   │
                      │           证书：你的域名 (Let's Encrypt)
                      └──────────────────────────────────────┘
```

- 公网只开 **80**（申请和续期证书）和 **443**（Xray）。
- **8443 不对外开放**。外面访问 `域名:8443` 连不上是正常的。
- 浏览器打开 `https://你的域名` 能看到网站，就说明伪装在工作。

## 文件

| 文件 | 作用 |
|---|---|
| `setup-site.sh` | 安装 Nginx + Certbot，部署网页，申请证书，让网站监听 `127.0.0.1:8443` |
| `reality-test.sh` | 在 VPS 上自己连自己，测试指定端口的 REALITY 入站能不能代理 |
| `reality-debug.sh` | 测试失败时用：起一个带完整日志的服务端副本，打印两边的日志 |
| `index.html`（可选） | 自己的网页；和 `setup-site.sh` 放在同一目录，运行时会自动使用 |

---

## 部署步骤

### 1. 域名解析

- 添加一条 **A 记录**：`你的域名 → VPS 的 IP`。
- 用 Cloudflare 的话，小云朵必须是**灰色（仅 DNS）**。
- 确认生效：在电脑上运行 `nslookup 你的域名`，解析结果应该是 VPS 的 IP。
- 服务商后台的安全组 / 防火墙要放行 **80、443**。

### 2. 搭建网站

把脚本传到 VPS 上（用 `scp`，或者 `nano setup-site.sh` 新建文件后粘贴内容），然后运行：

```bash
sudo bash setup-site.sh
```

按提示输入域名，邮箱可以直接回车跳过。最后的检查（TLS 1.3、h2、网页可访问）全部显示 ✔，并且脚本打印出 3x-ui 的填法，就成功了。

> 80 或 8443 被其他程序占用时，脚本会停下并提示，先处理占用再运行。

> **提示 `-bash: sudo: command not found` 怎么办？**
> 很多 VPS 系统没有预装 sudo。脚本只要求用 root 身份运行，不一定非要 sudo：
>
> - **命令行开头是 `root@...#`**：你已经是 root 了，去掉 `sudo` 直接运行：
>   ```bash
>   bash setup-site.sh
>   ```
> - **开头是 `用户名@...$`（普通用户）**：先切换到 root（输入 root 密码），再运行：
>   ```bash
>   su -
>   cd 脚本所在目录
>   bash setup-site.sh
>   ```
> - **以后想用 sudo**：在 root 下安装一次即可：`apt update && apt install -y sudo`
>
> 如果用普通用户直接运行，脚本会提示"请用 root 运行"并退出。

### 3. 在 3x-ui 里设置入站

**443 上只能有一个 REALITY 入站。** 有旧的入站就直接改它，或者先删掉再新建。

| 位置 | 设置项 | 填写 |
|---|---|---|
| 基础配置 | 端口 | `443` |
| 基础配置 | 协议 | `vless` |
| 协议 | 解密 / 加密 | 点 **清除**，确认 **解密 = `none`**（关闭 VLESS Encryption） |
| 协议 | 用户的 Flow | `xtls-rprx-vision` |
| 传输 | 传输方式 | `TCP (RAW)` |
| 安全 | 安全 | `Reality` |
| 安全 | uTLS | `chrome` |
| 安全 | **Target（Dest）** | `127.0.0.1:8443`（不是 `域名:8443`，也不是 `域名:443`） |
| 安全 | **SNI / Server Names** | 只填 `你的域名`，删掉其他所有值 |
| 安全 | Xver | `0` |
| 安全 | **mldsa65 Seed / Verify** | **清空** |
| 安全 | 密钥 | 点 **Get New Cert** 生成 |

保存。Vision testseed 等其他项保持默认。

### 4. 验证

```bash
# 伪装站：两段都应显示 Handshake succeeded，证书是你的域名
/usr/local/x-ui/bin/xray-linux-amd64 tls ping 你的域名

# 代理：应显示 ✔ 代理连接成功
bash reality-test.sh 443
```

> 粘贴多条命令时，注意每条单独一行，不要连在一起。

### 5. 客户端

- 从 3x-ui 复制 **443 入站**的分享链接导入客户端。改过入站设置后，要删掉旧节点重新导入。
- **推荐使用 Xray 内核的客户端**：v2rayNG（安卓）、v2rayN（Windows），并更新到最新版。
- 指纹（Fingerprint）选 `chrome`。
- Clash Meta / mihomo 和新版 Xray 服务端（26.9.8 及以后）有已知兼容问题：连接会被悄悄丢弃，两边都没有报错。

### 6. 收尾

```bash
rm -rf /root/reality-test     # 测试脚本生成的临时文件，里面有 UUID 和公钥
```

---

## 日常维护

**更换网页：** 用新的 `index.html` 覆盖 `/var/www/mysite/index.html`，不需要重启。或者把它和脚本放在同一目录，重新运行 `setup-site.sh`。

**每日变化：** 默认首页每天自动轮换"今日推荐"影片和列表顺序，大图右下角显示当天日期（`TODAY'S PICK · 30 OCT`），页脚年份自动更新。日期由 Nginx 的 SSI 在服务端写入页面（按服务器时区），不依赖任何外部服务；开启 SSI 后响应不再带 `Last-Modified` / `ETag`，和动态站点一致。旧版首页（`frame-video-v1`）重新运行 `setup-site.sh` 即可升级，原文件会先备份。

**证书续期：** certbot 会自动续期。可以偶尔检查一下：

```bash
certbot renew --dry-run
```

**改完配置后：** 每次在 3x-ui 里改了入站、更新了 Xray，都跑一遍：

```bash
bash reality-test.sh 443
```

---

## 故障排查

先运行 `bash reality-test.sh 443`：

- **✔ 成功，但手机连不上**：服务端没问题。检查手机里的参数是否和脚本打印的一致，客户端是不是 Clash（换 v2rayNG 试试），端口有没有放行。
- **✘ 失败**：运行 `bash reality-debug.sh 443`，对照下表看服务端日志。

| 现象 / 日志 | 原因 | 处理 |
|---|---|---|
| `tls ping` 报 `remote error: tls: internal error` | 443 入站的 Target 或 SNI 不对（比如还是旧的大站配置） | Target 改为 `127.0.0.1:8443`，SNI 只留你的域名 |
| 配置写在了别的端口 | 有多个 REALITY 入站，客户端连的那个没改 | 确认 443 那个入站是正确配置，删掉多余的 |
| `hs.handshake() err: payload[0]: 11, padding: -数字` | 开着 ML-DSA-65，自己的证书链太小（要求大于约 3500 字节） | 清空 mldsa65 Seed / Verify |
| `ML-KEM-768 handshake failed > ... message authentication failed` | 开着 VLESS Encryption，客户端不匹配 | 解密 / 加密点清除，解密 = `none` |
| 客户端报 `received real certificate` | 服务端没认出客户端（密钥、shortId、SNI 不一致，或客户端太旧） | 重新导入分享链接，更新客户端，指纹选 chrome |
| `processed invalid connection ... authentication failed` | 同上，或者是普通访客 / 探测（这种情况是正常的） | 只有你自己的客户端出现时才需要处理 |
| Clash 连不上，两边都没有报错 | mihomo 和新版 Xray 不兼容 | 换 v2rayNG；或者在 Clash 节点里设 `client-fingerprint: chrome`，再加 `reality-opts: support-x25519mlkem768: true` |
| 浏览器能打开网站，节点连不上，`nslookup` 解析不是 VPS 的 IP | 开了 Cloudflare 代理（橙色云朵） | 改成灰色（仅 DNS） |
| 外面访问 `域名:8443` 打不开 | 正常，8443 只对本机开放 | 不要对外开放 8443 |
| `-bash: sudo: command not found` | 系统没装 sudo | 已经是 root（提示符是 `#`）就去掉 sudo 直接运行；否则先 `su -` 切到 root，详见第 2 步 |
| `请用 root 运行` | 当前是普通用户 | `su -` 切到 root 后再运行 |

排查后如果需要恢复成默认状态，只要 Target、SNI、Xver、mldsa65、解密这五项和第 3 步的表一致就行。

---

## 常用命令速查

以下命令都要用 root 运行（提示符是 `#`）。没有 sudo 时直接去掉 `sudo`。

```bash
sudo bash setup-site.sh                                    # 搭建 / 重建网站
bash reality-test.sh 443                                   # 测试代理
bash reality-debug.sh 443                                  # 失败时看详细日志
/usr/local/x-ui/bin/xray-linux-amd64 tls ping 你的域名      # 测试伪装站
/usr/local/x-ui/bin/xray-linux-amd64 version               # Xray 版本
ss -ltnp | grep -E ':(80|443|8443)\b'                      # 端口占用
nginx -t && systemctl reload nginx                         # 检查并重载 Nginx
certbot renew --dry-run                                    # 检查证书续期
rm -rf /root/reality-test                                  # 清理测试临时文件
```
