#Requires AutoHotkey v2.0
#SingleInstance Force

; 铜仁云桌面（CUCloud）自动登录脚本
; 流程：启动 → 最大化 → 点「验证码登录」→ 输入手机号

; ===== 配置区 =====
; appPath   := "D:\App\cucloud\CUCloud\CUCloudClientiEntry\bin\CUCloudClientiEntry.exe"
appPath   := "C:\Program Files (x86)\CUCloudClientiEntry\CUCloud\CUCloudClientiEntry\bin\CUCloudClientiEntry.exe"
targetWin := "ahk_exe CUCloudClientiEntry.exe"
viewerWin := "ahk_exe uSmartView_VDI_Client.exe"
imgDir    := A_ScriptDir "\img"
phoneNum  := "18682253046"
maxRetries := 3
maxAttempts := maxRetries + 1

; ===== 日志配置 =====
logDir  := A_ScriptDir "\logs"
DirCreate(logDir)
logFile := logDir "\cucloud_" FormatTime(A_Now, "yyyyMMdd_HHmmss") ".log"
OnExit(LogScriptExit)
Log("脚本启动，日志文件：" . logFile)

; ImageSearch 默认局部搜索范围，依次为：左、上、右、下（窗口比例）
; 基于 2560×1494 客户区中的 (1300,630) 到 (2110,1225)，并预留少量边距
defaultSearchRegion := [0.49, 0.41, 0.84, 0.83]

CoordMode("Pixel", "Client")
CoordMode("Mouse", "Client")
Log(
    "配置加载完成，targetWin=" targetWin
    "，搜索区域=[" defaultSearchRegion[1] ", " defaultSearchRegion[2]
    ", " defaultSearchRegion[3] ", " defaultSearchRegion[4] "]"
)

; ===== 主流程 =====

loginSucceeded := false
Loop maxAttempts {
currentAttempt := A_Index
Log(
    "========== 登录流程开始，尝试=" currentAttempt
    "/" maxAttempts "（最多重试" maxRetries "次） =========="
)

; 1. 启动应用程序
Log("步骤1：准备启动 CUCloud，路径=" . appPath)
Run(appPath)
Log("步骤1：启动命令已发送")

; 2. 等待主窗口完成初始化，并反复尝试最大化（最多 60 秒）
Log("步骤2：等待主窗口并尝试最大化，超时=60秒")
maximized := false
deadline := A_TickCount + 60000
maximizeStartedAt := A_TickCount
lastWindowState := ""
while A_TickCount < deadline {
    hwnd := WinExist(targetWin)
    if hwnd {
        try {
            winTitle := "ahk_id " hwnd
            WinGetClientPos(&cX, &cY, &cW, &cH, winTitle)
            windowState := hwnd ":" cW "x" cH
            if windowState != lastWindowState {
                Log("步骤2：检测到窗口，hwnd=" hwnd "，客户区=" cW "x" cH)
                lastWindowState := windowState
            }
            ; 忽略启动画面或尚未完成布局的临时小窗口
            if cW >= 600 && cH >= 400 {
                if WinGetMinMax(winTitle) = -1
                    WinRestore(winTitle)
                WinActivate(winTitle)
                WinMaximize(winTitle)
                Sleep(500)
                if WinGetMinMax(winTitle) = 1 {
                    maximized := true
                    Log(
                        "步骤2：窗口最大化成功，hwnd=" hwnd
                        "，客户区=" cW "x" cH
                        "，耗时=" (A_TickCount - maximizeStartedAt) "ms"
                    )
                    break
                }
            }
        } catch as err {
            ; 启动页切换到主窗口时句柄可能失效，下一轮重新获取
            Log("步骤2：窗口暂不可用：" . err.Message, "WARN")
        }
    }
    Sleep(500)
}

if !maximized {
    Log("步骤2：60秒内未能最大化主窗口", "ERROR")
    MsgBox("CUCloud 主窗口在 60 秒内未能成功最大化。")
    ExitApp
}

; 4. 点击「验证码登录」按钮
;    截图：img\verify_login_btn.png；第 2、3 个参数填截图实际像素宽、高
Log("步骤4：开始查找并点击「验证码登录」")
if !FindAndClick(imgDir "\verify_login_btn.png", 120, 40) {
    Log("步骤4：未找到「验证码登录」", "ERROR")
    MsgBox("未找到「验证码登录」按钮。`n请检查 img\verify_login_btn.png 是否存在、清晰、DPI 一致。")
    ExitApp
}
Log("步骤4：「验证码登录」点击完成")

; 5. 点击手机号输入框并输入手机号
;    截图：img\phone_input.png（建议截含「请输入手机号」占位文字的输入框）；参数填宽、高
Log("步骤5：开始查找手机号输入框")
if !FindAndClick(imgDir "\phone_input.png", 200, 50) {
    Log("步骤5：未找到手机号输入框", "ERROR")
    MsgBox("未找到手机号输入框。`n请检查 img\phone_input.png 是否存在、清晰、DPI 一致。")
    ExitApp
}
Log("步骤5：手机号输入框已点击，准备输入")
Sleep(300)            ; 等输入框聚焦
Send("^a")            ; 全选清空，避免残留
SendText(phoneNum)    ; 输入手机号
Log("步骤5：手机号输入完成，长度=" . StrLen(phoneNum))

; 6. 按两次 Tab 聚焦「获取验证码」按钮，再按 Enter 点击
Log("步骤6：准备按两次 Tab 聚焦「获取验证码」")
Sleep(500)
Send("{Tab 2}")
Sleep(200)
Send("{Enter}")
Log("步骤6：已发送 Enter，开始等待验证码邮件，等待=120000ms")
Sleep(120000)  ; 点击成功后等待 120 秒，让验证码邮件到达
Log("步骤6：固定等待结束")

; 7. 调用 test.py 从邮箱读取验证码（邮件可能延迟到达，循环重试）
;    test.py 的 stdout 仅输出 6 位验证码；NOTFOUND/ERROR 表示尚未取到
verifyCode := ""
tmpFile    := A_Temp "\cucloud_verify_code.txt"
pyScript   := A_ScriptDir "\test.py"
out        := ""
Log("步骤7：准备调用 Python，脚本=" . pyScript)
if !FileExist(pyScript) {
    Log("步骤7：Python 脚本不存在", "ERROR")
    MsgBox("未找到 Python 脚本：`n" . pyScript)
    ExitApp
}
Loop 30 {                                  ; 最多等 30×2 = 60 秒
    attempt := A_Index
    Log("步骤7：第 " attempt "/30 次调用 test.py")
    try {
        pythonExitCode := RunWait(
            A_ComSpec ' /c python "' pyScript '" > "' tmpFile '"',
            ,
            "Hide"
        )
    } catch as err {
        Log("步骤7：test.py 启动异常：" . err.Message, "ERROR")
        Sleep(2000)
        continue
    }
    out := FileExist(tmpFile) ? Trim(FileRead(tmpFile)) : ""
    outSummary := RegExMatch(out, "^\d{6}$")
        ? "<已获得6位验证码>"
        : SubStr(StrReplace(StrReplace(out, "`r", " "), "`n", " "), 1, 200)
    Log(
        "步骤7：test.py 退出码=" pythonExitCode
        "，输出=" (outSummary = "" ? "<空>" : outSummary)
    )
    if RegExMatch(out, "^\d{6}$", &m) {    ; stdout 恰好为 6 位数字
        verifyCode := m[0]
        Log("步骤7：验证码获取成功，尝试次数=" . attempt)
        break
    }
    Sleep(2000)
}
if verifyCode = "" {
    Log("步骤7：30次轮询后仍未获得验证码", "ERROR")
    MsgBox("未能从邮件获取验证码。`n最近一次输出：" . out . "`n请手动运行 test.py 排查。")
    ExitApp
}

; 8. 点击验证码输入框并输入验证码
;    截图：img\code_input.png；参数填截图实际像素宽、高
Log("步骤8：开始查找验证码输入框")
if !FindAndClick(imgDir "\code_input.png", 200, 50) {
    Log("步骤8：未找到验证码输入框", "ERROR")
    MsgBox("未找到验证码输入框。`n请检查 img\code_input.png 是否存在、清晰、DPI 一致。")
    ExitApp
}
Log("步骤8：验证码输入框已点击，准备输入")
Sleep(300)
Send("^a")
SendText(verifyCode)
Log("步骤8：验证码输入完成，长度=" . StrLen(verifyCode))

; 9. 按三次 Tab 聚焦「登录」按钮，再按 Enter 点击
Log("步骤9：准备按三次 Tab 聚焦「登录」")
Sleep(500)
Send("{Tab 3}")
Sleep(2000)
Send("{Enter}")
Log("步骤9：已发送 Enter，登录操作提交完成")

; 10. 登录提交后等待远程桌面窗口出现
Log(
    "步骤10：等待远程桌面窗口，目标=" viewerWin
    "，超时=120秒，当前尝试=" currentAttempt "/" maxAttempts
)
viewerHwnd := WinWait(viewerWin,, 120)
if viewerHwnd {
    loginSucceeded := true
    try {
        WinGetPos(&viewerX, &viewerY, &viewerW, &viewerH, "ahk_id " viewerHwnd)
        Log(
            "步骤10：检测到远程桌面窗口，hwnd=" viewerHwnd
            "，位置=(" viewerX "," viewerY ")"
            "，尺寸=" viewerW "x" viewerH
            "，登录流程成功"
        )
    } catch as err {
        Log(
            "步骤10：检测到远程桌面窗口，hwnd=" viewerHwnd
            "，但读取窗口信息失败：" err.Message,
            "WARN"
        )
    }
    break
}

Log(
    "步骤10：120秒内未检测到远程桌面窗口，当前尝试失败",
    "ERROR"
)
ForceCloseCloudPrograms("第" currentAttempt "次登录失败后的清理")

if currentAttempt < maxAttempts {
    Log(
        "重试：3秒后重新执行整套流程，下一次="
        (currentAttempt + 1) "/" maxAttempts,
        "WARN"
    )
    Sleep(3000)
} else {
    Log("重试次数已耗尽，不再重新登录", "ERROR")
}
}

if !loginSucceeded {
    MsgBox(
        "登录失败：首次执行及后续 " maxRetries
        " 次重试均未检测到 uSmartView_VDI_Client.exe 窗口。"
    )
    ExitApp
}

; ===== 工具函数 =====

; 写入带时间戳的 UTF-8 日志；日志失败不影响主流程
Log(message, level := "INFO") {
    global logFile
    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    try FileAppend(
        "[" timestamp "][" level "] " message "`n",
        logFile,
        "UTF-8"
    )
}

LogScriptExit(exitReason, exitCode) {
    Log(
        "脚本退出，原因=" exitReason "，退出码=" exitCode,
        exitCode = 0 ? "INFO" : "ERROR"
    )
}

; 强制关闭登录客户端和远程桌面客户端，供失败重试及最终清理复用
ForceCloseCloudPrograms(reason := "") {
    global targetWin, viewerWin
    Log("进程清理：开始，原因=" . (reason = "" ? "<未指定>" : reason))
    processNames := [
        "uSmartView_VDI_Client.exe",
        "CUCloudClientiEntry.exe"
    ]
    for processName in processNames {
        if !ProcessExist(processName) {
            Log("进程清理：" processName " 未运行", "DEBUG")
            continue
        }
        Log("进程清理：准备结束 " . processName)
        try {
            exitCode := RunWait(
                A_ComSpec ' /d /c taskkill /F /T /IM "'
                    processName '" >nul 2>&1',
                ,
                "Hide"
            )
            Log(
                "进程清理：" processName " taskkill退出码=" exitCode,
                exitCode = 0 ? "INFO" : "WARN"
            )
        } catch as err {
            Log(
                "进程清理：" processName " taskkill异常：" err.Message,
                "ERROR"
            )
        }
    }

    if WinExist(viewerWin)
        WinWaitClose(viewerWin,, 10)
    if WinExist(targetWin)
        WinWaitClose(targetWin,, 10)

    remaining := []
    if ProcessExist("uSmartView_VDI_Client.exe")
        remaining.Push("uSmartView_VDI_Client.exe")
    if ProcessExist("CUCloudClientiEntry.exe")
        remaining.Push("CUCloudClientiEntry.exe")
    if remaining.Length
        Log("进程清理：仍有残留进程=" JoinText(remaining, ", "), "WARN")
    else
        Log("进程清理：完成，无残留目标进程")
}

JoinText(items, separator := ", ") {
    result := ""
    for item in items
        result .= (result = "" ? "" : separator) item
    return result
}

; 在目标窗口客户区的指定范围内查找图片并点击其中心
; region 使用窗口比例：[左, 上, 右, 下]；传入 0 时使用 defaultSearchRegion
; 返回：找到并点击返回 true，否则 false
FindAndClick(imgPath, w, h, retries := 10, region := 0) {
    global targetWin, defaultSearchRegion
    SplitPath(imgPath, &imgName)
    if !FileExist(imgPath) {
        Log("ImageSearch：图片不存在，path=" . imgPath, "ERROR")
        return false
    }
    try {
        WinGetClientPos(&cX, &cY, &cW, &cH, targetWin)
    } catch as err {
        Log("ImageSearch：" imgName " 无法获取窗口客户区：" err.Message, "ERROR")
        return false
    }
    if !IsObject(region)
        region := defaultSearchRegion
    x1 := Max(0, Floor(cW * region[1]))
    y1 := Max(0, Floor(cH * region[2]))
    x2 := Min(cW - 1, Ceil(cW * region[3]) - 1)
    y2 := Min(cH - 1, Ceil(cH * region[4]) - 1)
    tolerances := [2, 20, 40]              ; 逐级提高颜色容差，应对渲染/DPI 差异
    searchStartedAt := A_TickCount
    Log(
        "ImageSearch：开始，图片=" imgName
        "，客户区=" cW "x" cH
        "，范围=(" x1 "," y1 ")-(" x2 "," y2 ")"
        "，重试=" retries
    )
    Loop retries {
        attempt := A_Index
        for tol in tolerances {
            try {
                found := ImageSearch(
                    &fx,
                    &fy,
                    x1,
                    y1,
                    x2,
                    y2,
                    "*" tol " " imgPath
                )
            } catch as err {
                Log(
                    "ImageSearch：" imgName " 搜索异常：" err.Message,
                    "ERROR"
                )
                return false
            }
            if found {
                clickX := fx + w // 2
                clickY := fy + h // 2
                Click(clickX, clickY)
                Log(
                    "ImageSearch：命中，图片=" imgName
                    "，尝试=" attempt "/" retries
                    "，容差=" tol
                    "，左上=(" fx "," fy ")"
                    "，点击=(" clickX "," clickY ")"
                    "，耗时=" (A_TickCount - searchStartedAt) "ms"
                )
                return true
            }
        }
        Log(
            "ImageSearch：未命中，图片=" imgName
            "，尝试=" attempt "/" retries,
            "DEBUG"
        )
        Sleep(500)
    }
    Log(
        "ImageSearch：最终失败，图片=" imgName
        "，耗时=" (A_TickCount - searchStartedAt) "ms",
        "WARN"
    )
    return false
}

; 查找安装目录位于 \cucloud\ 下的全屏客户端窗口
FindCUCloudFullscreenWindow() {
    Log("断开连接：开始枚举 CUCloud 全屏窗口")
    for hwnd in WinGetList() {
        try {
            winTitle := "ahk_id " hwnd
            processPath := StrLower(ProcessGetPath(WinGetPID(winTitle)))
            style := WinGetStyle(winTitle)
            WinGetPos(&x, &y, &w, &h, winTitle)
            if InStr(processPath, "\cucloud\")
                && (style & 0x10000000)
                && w >= A_ScreenWidth * 0.9
                && h >= A_ScreenHeight * 0.9 {
                Log(
                    "断开连接：找到全屏窗口，hwnd=" hwnd
                    "，尺寸=" w "x" h
                    "，进程路径=" processPath
                )
                return hwnd
            }
        } catch {
            continue
        }
    }
    Log("断开连接：未找到 CUCloud 全屏窗口", "WARN")
    return 0
}

; 登录流程完成后等待 60 秒
Log("步骤11：登录成功后等待60秒，再尝试断开连接")
Sleep(60000)
Log("步骤11：60秒等待结束")

; 绕过被云桌面接管的鼠标键盘，直接请求全屏客户端正常关闭连接
remoteWin := FindCUCloudFullscreenWindow()
if remoteWin {
    Log("步骤11：向窗口发送正常关闭请求，hwnd=" . remoteWin)
    WinClose("ahk_id " remoteWin)
    WinWaitClose("ahk_id " remoteWin,, 10)
    if WinExist("ahk_id " remoteWin)
        Log("步骤11：等待10秒后窗口仍存在", "WARN")
    else
        Log("步骤11：窗口已正常关闭")
} else {
    Log("步骤11：跳过正常关闭，未找到目标全屏窗口", "WARN")
}

; 强制关闭 CUCloud 及远程桌面残留进程
Log("步骤12：开始最终进程清理")
ForceCloseCloudPrograms("登录成功并完成正常断开后的最终清理")
