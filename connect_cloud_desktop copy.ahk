#Requires AutoHotkey v2.0
#SingleInstance Force

; 铜仁云桌面（CUCloud）自动登录脚本
; 流程：启动 → 最大化 → 点「验证码登录」→ 输入手机号

; ===== 配置区 =====
appPath   := "D:\App\cucloud\CUCloud\CUCloudClientiEntry\bin\CUCloudClientiEntry.exe"
targetWin := "ahk_exe CUCloudClientiEntry.exe"
imgDir    := A_ScriptDir "\img"
phoneNum  := "18682253046"

CoordMode("Pixel", "Client")
CoordMode("Mouse", "Client")

; ===== 主流程 =====

; 1. 启动应用程序
Run(appPath)

; 2. 等待窗口出现（最多 30 秒）
WinWait(targetWin,, 30)

; 3. 激活并最大化窗口
WinActivate(targetWin)
WinMaximize(targetWin)

; 4. 点击「验证码登录」按钮
;    截图：img\verify_login_btn.png；第 2、3 个参数填截图实际像素宽、高
if !FindAndClick(imgDir "\verify_login_btn.png", 120, 40) {
    MsgBox("未找到「验证码登录」按钮。`n请检查 img\verify_login_btn.png 是否存在、清晰、DPI 一致。")
    ExitApp
}

; 5. 点击手机号输入框并输入手机号
;    截图：img\phone_input.png（建议截含「请输入手机号」占位文字的输入框）；参数填宽、高
if !FindAndClick(imgDir "\phone_input.png", 200, 50) {
    MsgBox("未找到手机号输入框。`n请检查 img\phone_input.png 是否存在、清晰、DPI 一致。")
    ExitApp
}
Sleep(300)            ; 等输入框聚焦
Send("^a")            ; 全选清空，避免残留
SendText(phoneNum)    ; 输入手机号

; 6. 点击「获取验证码」按钮
;    截图：img\get_code_btn.png；参数填截图实际像素宽、高
if !FindAndClick(imgDir "\get_code_btn.png", 120, 40) {
    MsgBox("未找到「获取验证码」按钮。`n请检查 img\get_code_btn.png 是否存在、清晰、DPI 一致。")
    ExitApp
}
Sleep(30000)  ; 点击成功后等待 30 秒，让验证码邮件到达

; 7. 调用 test.py 从邮箱读取验证码（邮件可能延迟到达，循环重试）
;    test.py 的 stdout 仅输出 6 位验证码；NOTFOUND/ERROR 表示尚未取到
verifyCode := ""
tmpFile    := A_Temp "\cucloud_verify_code.txt"
pyScript   := A_ScriptDir "\test.py"
out        := ""
Loop 30 {                                  ; 最多等 30×2 = 60 秒
    RunWait(A_ComSpec ' /c python "' pyScript '" > "' tmpFile '"',, "Hide")
    out := FileExist(tmpFile) ? Trim(FileRead(tmpFile)) : ""
    if RegExMatch(out, "^\d{6}$", &m) {    ; stdout 恰好为 6 位数字
        verifyCode := m[0]
        break
    }
    Sleep(2000)
}
if verifyCode = "" {
    MsgBox("未能从邮件获取验证码。`n最近一次输出：" . out . "`n请手动运行 test.py 排查。")
    ExitApp
}

; 8. 点击验证码输入框并输入验证码
;    截图：img\code_input.png；参数填截图实际像素宽、高
if !FindAndClick(imgDir "\code_input.png", 200, 50) {
    MsgBox("未找到验证码输入框。`n请检查 img\code_input.png 是否存在、清晰、DPI 一致。")
    ExitApp
}
Sleep(300)
Send("^a")
SendText(verifyCode)

; 9. 点击「登录」按钮
;    截图：img\login_btn.png；参数填截图实际像素宽、高
if !FindAndClick(imgDir "\login_btn.png", 780, 90) {
    MsgBox("未找到「登录」按钮。`n请检查 img\login_btn.png 是否存在、清晰、DPI 一致。")
    ExitApp
}

; ===== 工具函数 =====

; 在目标窗口客户区查找图片并点击其中心
; 参数：图片路径, 图片宽, 图片高, 重试次数(默认 15)
; 返回：找到并点击返回 true，否则 false
FindAndClick(imgPath, w, h, retries := 10) {
    global targetWin
    if !FileExist(imgPath)
        return false
    WinGetClientPos(&cX, &cY, &cW, &cH, targetWin)
    tolerances := [2, 20, 40]              ; 逐级提高颜色容差，应对渲染/DPI 差异
    Loop retries {
        for tol in tolerances {
            if ImageSearch(&fx, &fy, 0, 0, cW, cH, "*" tol " " imgPath) {
                Click(fx + w // 2, fy + h // 2)   ; 点击图片中心
                return true
            }
        }
        Sleep(500)
    }
    return false
}

; 查找安装目录位于 \cucloud\ 下的全屏客户端窗口
FindCUCloudFullscreenWindow() {
    for hwnd in WinGetList() {
        try {
            winTitle := "ahk_id " hwnd
            processPath := StrLower(ProcessGetPath(WinGetPID(winTitle)))
            style := WinGetStyle(winTitle)
            WinGetPos(&x, &y, &w, &h, winTitle)
            if InStr(processPath, "\cucloud\")
                && (style & 0x10000000)
                && w >= A_ScreenWidth * 0.9
                && h >= A_ScreenHeight * 0.9
                return hwnd
        } catch {
            continue
        }
    }
    return 0
}

; 登录流程完成后等待 60 秒
Sleep(60000)

; 绕过被云桌面接管的鼠标键盘，直接请求全屏客户端正常关闭连接
remoteWin := FindCUCloudFullscreenWindow()
if remoteWin {
    WinClose("ahk_id " remoteWin)
    WinWaitClose("ahk_id " remoteWin,, 10)
}

; 强制关闭 CUCloud 及其子进程
RunWait(
    A_ComSpec ' /d /c taskkill /F /T /IM CUCloudClientiEntry.exe >nul 2>&1',
    ,
    "Hide"
)
