@echo off
REM chcp 65001 >nul
REM 一键修改Chrome Local State文件中的三个参数

set "CHROME_LOCAL_STATE=F:\Cache\Chrome\User Data\Local State"

echo 正在修改Chrome Local State文件...
echo 文件路径: %CHROME_LOCAL_STATE%

echo 正在关闭 Chrome 浏览器...
REM 使用更强大的方法关闭 Chrome
powershell -Command "Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue"
timeout /t 3 /nobreak >nul 2>&1
powershell -Command "Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue"

echo 正在修改配置参数...
REM 检查文件是否存在
if not exist "%CHROME_LOCAL_STATE%" goto notfound

REM 创建临时文件
set "TEMP_FILE=%CHROME_LOCAL_STATE%.temp"

REM 使用 PowerShell 进行 JSON 处理和修改（使用 Select-Object 的 Add-Member 来添加新属性）
powershell -Command "$json = Get-Content -Path '%CHROME_LOCAL_STATE%' -Raw | ConvertFrom-Json; Add-Member -InputObject $json -NotePropertyName 'variations_permanent_consistency_country' -NotePropertyValue 'us' -Force; Add-Member -InputObject $json -NotePropertyName 'variations_country' -NotePropertyValue 'us' -Force; if ($json.profile.info_cache) { foreach ($profileName in $json.profile.info_cache.PSObject.Properties.Name) { Add-Member -InputObject $json.profile.info_cache.$profileName -NotePropertyName 'is_glic_eligible' -NotePropertyValue $true -Force } }; $json | ConvertTo-Json -Depth 100 | Set-Content -Path '%TEMP_FILE%' -Encoding UTF8 -NoNewline"

REM 检查是否成功
if not exist "%TEMP_FILE%" goto failed

REM 替换原文件
move /Y "%TEMP_FILE%" "%CHROME_LOCAL_STATE%" >nul
echo 修改成功！
goto success

:notfound
echo 错误: 找不到Local State文件！
echo 请确保Chrome的用户数据路径正确。
goto end

:failed
echo 修改失败！
echo 可能的原因：
echo 1. 权限不足，请尝试以管理员身份运行
echo 2. 文件被其他程序占用
echo 3. PowerShell执行策略限制
goto end

:success
echo 已成功修改以下参数：
echo variations_permanent_consistency_country = us
echo variations_country = us
echo is_glic_eligible = true

:end
pause
