# Misc Utils

个人常用工具和脚本集合。

## 📦 包含的工具

### 1. Unsloth Studio 安装脚本
- **文件**: `install.ps1`
- **功能**: Windows 下自动安装 Unsloth Studio（AI 模型推理和微调平台）
- **特点**: 
  - 支持自定义安装路径（D: 盘）
  - 自动处理盘符不匹配问题
  - CPU-only 模式支持

### 2. OpenAI 注册自动化
- **文件**: `openai_register.py`, `gaojilingjuli_openai_regst.py`
- **功能**: OpenAI 账号注册自动化工具

### 3. Cloudflare Workers 代理
- **文件**: `wh-cfnew.js`
- **功能**: Cloudflare Workers 代理脚本，支持多种协议（VLESS, Trojan, xhttp）

### 4. 其他工具
- `snippets.js`: 代码片段集合
- `启用Gemini_in_Chrome.bat`: Chrome 浏览器启用 Gemini 的批处理脚本
- `ai_prompts.md`: AI 提示词模板
- `system_instructions.md`: 系统指令文档

## 🚀 快速开始

### 安装 Unsloth Studio

```powershell
.\install.ps1
```

安装完成后启动：

```powershell
D:\Users\wh898\.unsloth\studio\unsloth_studio\Scripts\unsloth.exe studio -H 0.0.0.0 -p 8888
```

然后访问 http://localhost:8888

## ⚙️ 环境要求

- Python 3.11-3.13
- Windows 10/11
- Git
- CMake
- Visual Studio Build Tools（可选，用于编译）

## 📝 注意事项

1. **路径配置**: 本项目的 install.ps1 已修改为支持 D: 盘安装
2. **CPU 模式**: 当前配置为 CPU-only，适合推理但不适合训练
3. **符号链接**: 安装了 C: 到 D: 的符号链接以兼容 unsloth CLI

## 🔧 常见问题

### Studio 无法启动
确保符号链接已创建：
```powershell
New-Item -ItemType SymbolicLink -Path "C:\Users\wh898\.unsloth" -Target "D:\Users\wh898\.unsloth" -Force
```

### 模型下载慢
可以使用国内镜像或代理加速。

## 📄 许可证

本项目仅供个人学习和研究使用。

## 👤 作者

个人项目集合
