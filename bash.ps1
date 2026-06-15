# =========================================================================
# 1. 动态获取 Scoop 安装的 Git 路径及图标（彻底拆分 JSON 与 注册表 变量）
# =========================================================================
$gitExe = Get-Command git -ErrorAction SilentlyContinue
if (!$gitExe) {
    Write-Host "❌ 未找到 git 命令，请确保 Scoop 已正确安装并配置 Git！" -ForegroundColor Red
    Exit
}
$gitRoot = Split-Path (Split-Path $gitExe.Source) -Parent

# 纯净的单反斜杠路径（专门供 Windows Terminal JSON 使用）
$bashExePure = Join-Path $gitRoot "bin\bash.exe"
$iconPathPure = Join-Path $gitRoot "mingw64\share\git\git-for-windows.ico"

# 专门供注册表使用的双反斜杠转义路径
$escapedIconPath = $iconPathPure.Replace("\", "\\")

$menuName = "在此处打开 Git Bash"

# =========================================================================
# 2. 智能扫描 Windows Terminal (WT) 配置（修正并补全高级属性）
# =========================================================================
$wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

if (Test-Path $wtSettingsPath) {
    Write-Host "🔍 正在扫描 Windows Terminal 配置文件..." -ForegroundColor Cyan
    
    # 读取并解析 JSON 文件
    $jsonRaw = Get-Content -Path $wtSettingsPath -Raw -Encoding Utf8
    $settings = $jsonRaw | ConvertFrom-Json
    
    # 查找是否已存在 Git Bash 项
    $existingProfile = $settings.profiles.list | Where-Object { $_.name -eq "Git Bash" -or $_.commandline -like "*bash.exe*" }
    
    if ($existingProfile) {
        $guid = $existingProfile.guid
        Write-Host "✨ 找到已存在的 Git Bash 配置，提取 GUID: $guid" -ForegroundColor Green
        
        # 【核心修正】不管之前有没有写错，强行用纯净路径覆盖，依靠 ConvertTo-Json 自动生成规范的双斜杠
        Write-Host "🔧 正在为您修正并补全 Windows Terminal 高级属性..." -ForegroundColor Yellow
        $existingProfile | Add-Member -NotePropertyName "commandline" -NotePropertyValue "`"$bashExePure`" -i -l" -Force
        $existingProfile | Add-Member -NotePropertyName "icon" -NotePropertyValue "$iconPathPure" -Force
        $existingProfile | Add-Member -NotePropertyName "startingDirectory" -NotePropertyValue "%USERPROFILE%" -Force
        
        # 回写 JSON 文件
        $updatedJson = ConvertTo-Json $settings -Depth 100
        [System.IO.File]::WriteAllText($wtSettingsPath, $updatedJson, [System.Text.Encoding]::UTF8)
        Write-Host "✅ Windows Terminal 的四个斜杠已被完美修正为标准双斜杠！" -ForegroundColor Green
        
    } else {
        # 没找到任何相关项，全新注入
        $guid = "{" + [Guid]::NewGuid().ToString() + "}"
        Write-Host "💡 未找到 Git Bash，自动为您创建新配置..." -ForegroundColor Yellow
        
        $newProfile = [PSCustomObject]@{
            commandline       = "`"$bashExePure`" -i -l"
            guid              = $guid
            hidden            = $false
            icon              = $iconPathPure
            name              = "Git Bash"
            startingDirectory = "%USERPROFILE%"
        }
        $settings.profiles.list += $newProfile
        
        $updatedJson = ConvertTo-Json $settings -Depth 100
        [System.IO.File]::WriteAllText($wtSettingsPath, $updatedJson, [System.Text.Encoding]::UTF8)
        Write-Host "✅ 已成功将规范的 Git Bash 配置写入 Windows Terminal！" -ForegroundColor Green
    }
} else {
    $guid = "{2ece5bfe-50ed-5f3a-ab87-5cd4baafed2b}"
    Write-Host "⚠️ 未检测到 Windows Terminal 配置文件，将使用默认备用 GUID。" -ForegroundColor DarkYellow
}

# =========================================================================
# 3. 交互式选择：面向当前用户 or 全电脑
# =========================================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 请选择 [在此处打开 Git Bash] 右键菜单的安装范围：" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 1. 仅针对当前用户 (无需管理员权限，推荐 Scoop 用户)" -ForegroundColor Green
Write-Host " 2. 针对全电脑用户 (需要管理员权限)" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$choice = Read-Host "请输入数字 (1 或 2)"

if ($choice -eq "1") {
    $regRoot = "HKEY_CURRENT_USER\Software\Classes"
    $needAdmin = $false
} elseif ($choice -eq "2") {
    $regRoot = "HKEY_CLASSES_ROOT"
    $needAdmin = $true
} else {
    Write-Host "❌ 输入错误，脚本已退出。" -ForegroundColor Red
    Exit
}

# =========================================================================
# 4. 动态生成注册表内容并利用 .NET 无损写入（注册表必须保留手动转义的双斜杠）
# =========================================================================
$regCode = @"
Windows Registry Editor Version 5.00

; 文件夹背景右键
[$regRoot\Directory\Background\shell\OpenGitBash]
@="$menuName"
"Icon"="$escapedIconPath"

[$regRoot\Directory\Background\shell\OpenGitBash\command]
@="wt.exe -p \"$guid\" -d \"%V.\""

; 文件夹图标右键
[$regRoot\Directory\shell\OpenGitBash]
@="$menuName"
"Icon"="$escapedIconPath"

[$regRoot\Directory\shell\OpenGitBash\command]
@="wt.exe -p \"$guid\" -d \"%1.\""
"@

$tempPath = "$env:TEMP\git_bash_scoop.reg"
[System.IO.File]::WriteAllText($tempPath, $regCode, [System.Text.Encoding]::Unicode)

# =========================================================================
# 5. 智能判定提权并导入注册表，最后自动清理垃圾
# =========================================================================
if ($needAdmin) {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        regedit.exe /s $tempPath
        Write-Host "✅ 成功以当前管理员权限导入全电脑右键菜单！" -ForegroundColor Green
    } else {
        Write-Host "🚀 正在请求管理员权限以修改全电脑注册表..." -ForegroundColor Cyan
        Start-Process "regedit.exe" -ArgumentList "/s `"$tempPath`"" -Verb RunAs
        Write-Host "✅ 提权导入指令已发出，请在弹出的系统窗口中点击'是'。" -ForegroundColor Green
    }
} else {
    regedit.exe /s $tempPath
    Write-Host "✅ 成功导入当前用户右键菜单！" -ForegroundColor Green
}

if (Test-Path $tempPath) { Remove-Item $tempPath -Force }
Write-Host "🎉 脚本执行完毕！" -ForegroundColor Green
