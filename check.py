#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import json
import requests
from pathlib import Path

# ====================== 配置区域 ======================
BETAS = [
    {"id": "VCIvwk2g", "name": "QuantumultX"},
    {"id": "E338vEDz", "name": "Lettera"},
    {"id": "rnalqGZv", "name": "Bear"},
]

BARK_KEY = os.getenv("BARK_KEY", "")
BARK_SERVER = os.getenv("BARK_SERVER", "https://api.day.app")
STATE_FILE = Path("tf_state.json")
# ====================================================


def get_testflight_id(tf: str) -> str:
    tf = tf.strip().rstrip("/")
    if "testflight.apple.com" in tf:
        return tf.split("/")[-1].split("?")[0]
    return tf


def check_status(tf_id: str) -> str:
    """返回 open / full / closed / error"""
    url = f"https://testflight.apple.com/join/{tf_id}"
    headers = {
        "Accept-Language": "en-US,en;q=0.9",
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }

    try:
        resp = requests.get(url, headers=headers, timeout=15)
        text = resp.text.lower()  # 全部转小写，避免大小写和特殊引号问题

        # 1. 已满
        if "this beta is full" in text or "测试员已满" in text or "beta 版本的测试员已满" in text:
            return "full"

        # 2. 不接受新测试员（最关键）
        if ("isn't accepting" in text or 
            "isn’t accepting" in text or 
            "not accepting" in text or
            "不接受任何新的测试员" in text or
            "目前不接受" in text):
            return "closed"

        # 3. 有空位的特征（更严格）
        # 只有出现这些明确引导加入的文案才认为是 open
        if ("to join the" in text and "open the link on your" in text) or \
           "start testing" in text or \
           "开始测试" in text:
            return "open"

        # 4. 其他情况默认 closed，避免误报
        return "closed"

    except Exception as e:
        print(f"检查 {tf_id} 失败: {e}")
        return "error"


def send_bark(title: str, body: str, url: str = None):
    if not BARK_KEY:
        print("未配置 BARK_KEY，跳过推送")
        return

    payload = {
        "title": title,
        "body": body,
        "group": "TestFlight",
        "level": "timeSensitive",
    }
    if url:
        payload["url"] = url

    try:
        api = f"{BARK_SERVER.rstrip('/')}/{BARK_KEY}"
        resp = requests.post(api, json=payload, timeout=10)
        print(f"Bark 推送结果: {resp.status_code} - {resp.text}")
    except Exception as e:
        print(f"Bark 推送失败: {e}")


def load_state() -> dict:
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except:
            pass
    return {}


def save_state(state: dict):
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def main():
    print("开始检查 TestFlight 状态...")
    old_state = load_state()
    new_state = {}

    for beta in BETAS:
        tf_id = get_testflight_id(beta["id"])
        name = beta.get("name") or tf_id
        status = check_status(tf_id)
        new_state[tf_id] = status

        print(f"{name} ({tf_id}): {status}")

        prev = old_state.get(tf_id)

        # 只有从非 open → open 时才通知
        if status == "open" and prev != "open":
            title = f"🎉 {name} 有空位了！"
            body = f"TestFlight 现在可以加入\nhttps://testflight.apple.com/join/{tf_id}"
            send_bark(title, body, url=f"https://testflight.apple.com/join/{tf_id}")
            print(f"→ 已推送通知: {name}")

    save_state(new_state)
    print("检查完成")


if __name__ == "__main__":
    main()
