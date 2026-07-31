import imaplib
import email
import os
import re
import sys

# 登录邮箱（账号和授权码从系统环境变量读取）
EMAIL_ACCOUNT = os.environ.get("EMAIL_ACCOUNT")
EMAIL_PASSWORD = os.environ.get("EMAIL_PASSWORD")

if not EMAIL_ACCOUNT or not EMAIL_PASSWORD:
    print("ERROR:env")
    raise SystemExit(1)

try:
    mail = imaplib.IMAP4_SSL("imap.qq.com")  # 按你邮箱改
    mail.login(EMAIL_ACCOUNT, EMAIL_PASSWORD)
    mail.select("inbox")

    # 获取未读邮件
    result, data = mail.search(None, "UNSEEN")
    ids = data[0].split()
    if not ids:
        print("NOTFOUND")          # 还没收到验证码邮件
        raise SystemExit(0)

    latest_email_id = ids[-1]
    result, msg_data = mail.fetch(latest_email_id, "(RFC822)")
    msg = email.message_from_bytes(msg_data[0][1])

    # 提取正文
    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            if "attachment" in str(part.get("Content-Disposition")):
                continue
            if part.get_content_type() in ("text/plain", "text/html"):
                charset = part.get_content_charset() or "utf-8"
                try:
                    body += part.get_payload(decode=True).decode(charset, errors="ignore")
                except Exception:
                    pass
    else:
        charset = msg.get_content_charset() or "utf-8"
        body = msg.get_payload(decode=True).decode(charset, errors="ignore")

    # 正文输出到 stderr，便于手动调试（不影响 AHK 读取 stdout）
    print(body, file=sys.stderr)

    # 提取 6 位验证码（正则已用分组捕获，直接取 group(1)，兼容半角/全角冒号）
    match = re.search(r"验证码为[:：]\s*(\d{6})", body)
    print(match.group(1) if match else "NOTFOUND")
except Exception as e:
    print("ERROR:" + type(e).__name__)
