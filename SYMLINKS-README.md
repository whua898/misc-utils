# C盘软连接管理工具集

## 📋 概述

本工具集用于管理C盘的符号链接(软连接),帮助你将大文件/目录迁移到其他磁盘以节省C盘空间,并提供备份和恢复功能。

## 🛠️ 工具列表

### 1. migrate-logitech-disk.ps1
**用途**: 将Logitech相关目录从C盘迁移到D盘并创建软连接

**功能**:
- 自动检测并终止占用进程
- 复制数据到D:\ProgramData
- 删除C盘原目录
- 创建软连接指向D盘
- 验证软连接是否成功

**使用方法**:
```powershell
# 需要管理员权限
.\migrate-logitech-disk.ps1
```

**迁移的目录**:
- `C:\ProgramData\LogiOptionsPlus` → `D:\ProgramData\LogiOptionsPlus`
- `C:\ProgramData\Logishrd` → `D:\ProgramData\Logishrd`

---

### 2. export-symlinks.ps1
**用途**: 导出C盘所有软连接信息到JSON文件,用于备份

**功能**:
- 扫描C盘关键目录的所有软连接
- 记录源路径、目标路径、类型等信息
- 导出为 symlinks-backup.json 文件
- 显示统计信息和分布情况

**使用方法**:
```powershell
.\export-symlinks.ps1
```

**扫描的目录**:
- C:\ProgramData
- C:\Program Files
- C:\Program Files (x86)
- C:\Users\wh898
- C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\WindowsApps

**输出文件**: `symlinks-backup.json`

**建议**: 
- 定期运行此脚本备份软连接配置
- 将JSON文件保存到云盘或U盘等安全位置
- 系统重装前务必备份

---

### 3. restore-symlinks.ps1
**用途**: 根据备份恢复C盘所有软连接

**功能**:
- 读取预定义的软连接配置
- 检查目标路径是否存在
- 自动创建软连接
- 跳过已存在的软连接
- 提供详细的执行报告和统计

**使用方法**:
```powershell
# 需要管理员权限
.\restore-symlinks.ps1
```

**恢复的软连接** (共21个):

#### ProgramData (2个)
- LogiOptionsPlus → D:\ProgramData\LogiOptionsPlus
- Logishrd → D:\ProgramData\Logishrd

#### Program Files (2个)
- Adobe HelpCfg → F:\Oftenused\adobe\Photoshop\App\Program Files\Common Files\Adobe\HelpCfg
- Autodesk AdskLicensing → C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\15.3.0.12981

#### 用户目录 (16个)
所有用户配置目录都已迁移到 D:\Users\wh898\:
- .android (Android SDK)
- .antigravity / .antigravity_tools
- .cache (缓存)
- .cherrystudio (Cherry Studio)
- .claude (Claude AI)
- .cline (Cline)
- .continue (Continue)
- .fiddler (Fiddler抓包工具)
- .gemini (Gemini AI)
- .hvigor (Hvigor构建工具)
- .lingma (通义灵码)
- .ohpm (OpenHarmony包管理器)
- .qwen (通义千问)
- .ssh (SSH密钥)
- PCManger\mdfs (腾讯电脑管家卷挂载点)

#### 需要手动处理 (1个)
- Autodesk Network License Manager .logger (目标路径未知)

---

## 📊 当前软连接统计

根据最新备份 (symlinks-backup.json):
- **总计**: 25个软连接
- **目录链接**: 20个
- **文件链接**: 5个 (Windows系统应用)

---

## 💡 使用场景

### 场景1: C盘空间不足
1. 使用 `migrate-logitech-disk.ps1` 迁移大型应用数据
2. 或手动迁移其他大目录后,使用 `New-Item -ItemType SymbolicLink` 创建软连接
3. 运行 `export-symlinks.ps1` 备份配置

### 场景2: 系统重装前准备
1. 运行 `export-symlinks.ps1` 导出当前所有软连接
2. 将 `symlinks-backup.json` 保存到外部存储
3. 记录D盘或其他盘的数据位置

### 场景3: 系统重装后恢复
1. 确保D盘等数据盘的数据已就绪
2. 以管理员身份运行 `restore-symlinks.ps1`
3. 检查报告,手动处理需要确认的项目

---

## ⚠️ 注意事项

1. **管理员权限**: 创建软连接需要管理员权限
2. **目标路径**: 恢复前确保所有目标路径的数据已存在
3. **编码问题**: 脚本必须使用UTF-8 BOM编码,否则可能执行失败
4. **进程占用**: 迁移时如有进程占用文件,脚本会尝试终止,但可能需要手动关闭
5. **测试验证**: 恢复后请测试相关应用程序是否正常工作

---

## 🔧 手动创建软连接

如果需要手动创建软连接:

```powershell
# 目录软连接
New-Item -ItemType SymbolicLink -Path "C:\目标路径" -Target "D:\源路径"

# 文件软连接
New-Item -ItemType SymbolicLink -Path "C:\目标文件" -Target "D:\源文件"

# 查看软连接
Get-Item "C:\目标路径" | Select-Object FullName, Target
```

---

## 📝 维护建议

1. **定期备份**: 每次新增软连接后,运行 `export-symlinks.ps1` 更新备份
2. **文档更新**: 如修改了 `restore-symlinks.ps1`,记得更新本文档
3. **测试恢复**: 定期在测试环境验证恢复脚本的有效性
4. **版本控制**: 将这些脚本纳入Git版本控制

---

## 🆘 故障排除

### 问题1: 脚本执行报错"缺少右}"
**原因**: 文件编码不正确  
**解决**: 使用UTF-8 BOM编码保存文件

### 问题2: 创建软连接失败"拒绝访问"
**原因**: 没有管理员权限  
**解决**: 以管理员身份运行PowerShell

### 问题3: 目标路径不存在
**原因**: 数据未迁移或路径错误  
**解决**: 检查目标路径,确保数据已正确复制

### 问题4: 软连接创建成功但程序无法使用
**原因**: 某些程序不支持软连接  
**解决**: 查阅程序文档,可能需要其他迁移方案

---

## 📦 相关文件

- `migrate-logitech-disk.ps1` - Logitech目录迁移脚本
- `export-symlinks.ps1` - 软连接导出/备份脚本
- `restore-symlinks.ps1` - 软连接恢复脚本
- `symlinks-backup.json` - 软连接备份数据(JSON格式)
- `SYMLINKS-README.md` - 本文档

---

## 📅 更新日志

### 2026-04-16
- 初始版本
- 完成Logitech目录迁移
- 导出25个软连接配置
- 创建完整的备份和恢复工具链

---

## 👤 作者

系统管理员自动化脚本集合

---

**最后更新**: 2026-04-16
