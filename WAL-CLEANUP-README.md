# CapabilityAccessManager.db-wal 文件清理工具

## 🔍 问题说明

`CapabilityAccessManager.db-wal` 是 Windows 能力访问管理器数据库的 WAL (Write-Ahead Logging) 日志文件。

### 为什么会无限增长?

1. **数据库检查点失败** - WAL 日志无法正常合并到主数据库
2. **进程持续占用** - CamSvc 服务频繁读写但不释放
3. **权限问题** - 系统账户无法执行维护操作
4. **Windows Bug** - 某些版本存在已知缺陷,曾报告达到 34GB+

### 影响

- ❌ 占用大量C盘空间(可达数十GB)
- ❌ 可能导致系统性能下降
- ❌ 磁盘空间不足警告

---

## 🛠️ 解决方案

### 方案1: 手动立即清理(推荐首次使用)

```powershell
# 以管理员身份运行 PowerShell
.\cleanup-capability-wal.ps1
```

**脚本功能:**
- ✅ 自动查找所有可能的 WAL 文件位置
- ✅ 停止 CamSvc 服务
- ✅ 备份主数据库文件
- ✅ 删除 WAL 和 SHM 临时文件
- ✅ 重启服务
- ✅ 显示清理结果

---

### 方案2: 创建自动清理任务(推荐长期使用)

```powershell
# 以管理员身份运行
.\create-wal-cleanup-task.ps1
```

**自动任务配置:**
- 📅 执行频率: 每周日凌晨 2:00
- 🔐 运行身份: SYSTEM (最高权限)
- ⏱️ 超时限制: 1小时
- 🔄 失败重试: 3次
- 💾 自动备份: 每次清理前备份数据库

---

### 方案3: 手动命令清理

```powershell
# 1. 停止服务
Stop-Service -Name "CamSvc" -Force

# 2. 删除 WAL 文件
Remove-Item "C:\ProgramData\Microsoft\Windows\AppRepository\CapabilityAccessManager.db-wal" -Force
Remove-Item "C:\ProgramData\Microsoft\Windows\AppRepository\CapabilityAccessManager.db-shm" -Force

# 3. 重启服务
Start-Service -Name "CamSvc"
```

---

## 📊 监控 WAL 文件大小

### 快速检查

```powershell
# 检查文件大小
Get-ChildItem "C:\ProgramData\Microsoft\Windows\AppRepository\CapabilityAccessManager.db*" | 
    Select-Object Name, @{Name="Size(MB)";Expression={[math]::Round($_.Length/1MB,2)}}
```

### 设置大小警报

```powershell
# 如果超过 1GB,发出警告
$file = Get-Item "C:\ProgramData\Microsoft\Windows\AppRepository\CapabilityAccessManager.db-wal" -ErrorAction SilentlyContinue
if ($file -and $file.Length -gt 1GB) {
    Write-Host "警告: WAL 文件已超过 1GB!" -ForegroundColor Red
    Write-Host "当前大小: $([math]::Round($file.Length/1GB, 2)) GB" -ForegroundColor Yellow
}
```

---

## 🔧 根本解决方案

如果 WAL 文件频繁增长,可能需要:

### 1. 更新 Windows
```powershell
# 检查并安装最新补丁
winget install --id Microsoft.WindowsAppRuntime
```

### 2. 重置 AppRepository 数据库

```powershell
# 警告: 这会重置所有应用权限设置!
# 仅在问题严重时使用

Stop-Service -Name "CamSvc" -Force
Remove-Item "C:\ProgramData\Microsoft\Windows\AppRepository\CapabilityAccessManager.db*" -Force
Start-Service -Name "CamSvc"
```

### 3. 检查系统日志

```powershell
# 查看相关错误日志
Get-EventLog -LogName Application -Source "Microsoft-Windows-AppXDeploymentServer" -Newest 50 | 
    Where-Object { $_.EntryType -eq "Error" } |
    Format-Table TimeGenerated, Message -AutoSize
```

---

## 📁 工具文件说明

| 文件名 | 用途 | 执行频率 |
|--------|------|----------|
| `cleanup-capability-wal.ps1` | 清理 WAL 文件脚本 | 按需或定期 |
| `create-wal-cleanup-task.ps1` | 创建自动清理计划任务 | 仅一次 |
| `WAL-CLEANUP-README.md` | 本文档 | - |

---

## ⚠️ 注意事项

1. **管理员权限**: 所有操作都需要管理员权限
2. **备份安全**: 脚本会自动备份数据库,清理后建议保留备份几天
3. **服务影响**: 停止 CamSvc 期间,UWP应用权限检查可能暂时失效
4. **文件大小阈值**: 脚本默认只清理超过 100MB 的文件
5. **编码要求**: 脚本必须使用 UTF-8 BOM 编码

---

## 🆘 故障排除

### 问题1: 无法停止 CamSvc 服务
**解决**: 
```powershell
# 强制终止进程
Get-Process | Where-Object {$_.ProcessName -like "*CamSvc*"} | Stop-Process -Force
```

### 问题2: 删除文件时提示"正在使用"
**解决**:
- 确保服务已完全停止
- 等待 5-10 秒后再试
- 重启电脑后立即执行清理

### 问题3: 清理后 WAL 文件迅速再次增长
**解决**:
- 检查 Windows 更新,安装最新补丁
- 运行系统文件检查: `sfc /scannow`
- 考虑重置整个 AppRepository 数据库

### 问题4: 计划任务未执行
**检查**:
```powershell
# 查看任务状态
Get-ScheduledTask -TaskName "Cleanup-CapabilityAccessManager-WAL" | 
    Get-ScheduledTaskInfo

# 查看历史记录
Get-ScheduledTask -TaskName "Cleanup-CapabilityAccessManager-WAL" | 
    Get-ScheduledTaskInfo | 
    Select-Object LastRunTime, LastTaskResult, NextRunTime
```

---

## 📝 使用流程建议

### 首次使用
1. 运行 `cleanup-capability-wal.ps1` 立即清理
2. 检查清理效果,确认系统正常
3. 运行 `create-wal-cleanup-task.ps1` 创建自动任务

### 日常维护
- 自动任务会每周执行,无需手动干预
- 每月检查一次任务执行记录
- 如发现问题,手动运行清理脚本

### 系统重装后
- 重新复制这两个脚本
- 重新创建计划任务

---

## 🔗 相关资源

- [Microsoft Docs: SQLite WAL Mode](https://www.sqlite.org/wal.html)
- [Windows AppContainer 文档](https://docs.microsoft.com/en-us/windows/win32/secauthz/appcontainer-isolation)
- [计划任务管理](https://docs.microsoft.com/en-us/powershell/module/scheduledtasks/)

---

## 📅 更新日志

### 2026-04-16
- 初始版本
- 创建自动清理脚本
- 添加计划任务自动化
- 编写完整文档

---

**最后更新**: 2026-04-16  
**适用系统**: Windows 10/11  
**需要权限**: 管理员
