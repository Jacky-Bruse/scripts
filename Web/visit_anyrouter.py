import os
import requests
import time
from datetime import datetime

url = "https://anyrouter.top/console"

cookie = os.getenv("ANYROUTER_COOKIE")

headers = {
    "User-Agent": "Mozilla/5.0",
    "Cookie": cookie or ""
}

try:
    print("开始访问：", datetime.now())

    response = requests.get(url, headers=headers, timeout=20, allow_redirects=True)
    print("最终网址：", response.url)
    print("状态码：", response.status_code)
    print("页面长度：", len(response.text))

    if "login" in response.url.lower():
        print("可能未登录：请求被跳转到登录页")

    print("等待 30 秒后退出")
    time.sleep(30)

    print("任务结束：", datetime.now())

except Exception as e:
    print("访问失败：", e)
