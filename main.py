import imaplib
import email
import re

mail = imaplib.IMAP4_SSL("imap.qq.com")  # 根据邮箱改
mail.login("2032332852@qq.com", "erxigtbbymladced")

mail.select("inbox")

result, data = mail.search(None, "UNSEEN")
print(data)
latest_email_id = data[0].split()[-1]

result, msg_data = mail.fetch(latest_email_id, "(RFC822)")

msg = email.message_from_bytes(msg_data[0][1])
# print(msg)
content = msg.as_string()
print(content)
# 提取6位验证码
code = re.search(r"\d{6}", content).group()

print(code)