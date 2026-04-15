# Misc Utils

个人常用工具和脚本集合。

## 📦 包含的工具

### 1. Unsloth Studio 安装脚本
- **文件**: `Unsloth-install.ps1`
- **功能**: Windows 下自动安装 Unsloth Studio（AI 模型推理和微调平台）
- **特点**: 
  - 硬编码安装到 D: 盘，避免占用 C: 盘
  - Node.js/npm 自动检测和升级
  - 依赖完整性验证（structlog, fastapi 等）
  - winget 缺失时的友好处理
  - 网络下载重试机制
  - 支持 CPU-only 模式

### 2. 模型下载工具
- **文件**: `download_model.py`
- **功能**: 从 HuggingFace 下载 AI 模型，支持国内镜像
- **支持模型**:
  - Qwen2.5 系列（0.5B ~ 7B）
  - Llama 3.x 系列（1B ~ 8B）
  - Gemma 2/4 系列（2B ~ 31B）
  - GGUF 格式模型（手动下载指引）
- **特点**:
  - 支持 hf-mirror.com 国内镜像加速
  - 断点续传
  - 硬件适配推荐（GTX 1660 6GB）

### 3. OpenAI 注册自动化
- **文件**: `openai_register.py`, `gaojilingjuli_openai_regst.py`
- **功能**: OpenAI 账号注册自动化工具

### 4. Cloudflare Workers 代理
- **文件**: `wh-cfnew.js`
- **功能**: Cloudflare Workers 代理脚本，支持多种协议（VLESS, Trojan, xhttp）

### 5. 其他工具
- `snippets.js`: 代码片段集合
- `启用Gemini_in_Chrome.bat`: Chrome 浏览器启用 Gemini 的批处理脚本
- `ai_prompts.md`: AI 提示词模板
- `system_instructions.md`: 系统指令文档

## 🚀 快速开始

### 安装 Unsloth Studio

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Unsloth-install.ps1
```

安装完成后启动（使用快捷方式）：

```powershell
# 方式 1: 双击桌面快捷方式 "Unsloth Studio.lnk"

# 方式 2: 使用批处理文件
.\start-unsloth.bat

# 方式 3: 手动启动
D:\Users\wh898\.unsloth\studio\unsloth_studio\Scripts\unsloth.exe studio -H 0.0.0.0 -p 8888
```

然后访问 http://localhost:8888

**默认账户**:
- 用户名: `unsloth`
- 密码: 查看 `D:\Users\wh898\.unsloth\studio\auth\.bootstrap_password`

### 下载模型

```powershell
python download_model.py
```

选择模型后会自动从 HuggingFace（国内镜像）下载。

### 测试 Unsloth

```powershell
python test_unsloth.py
```

## ⚙️ 环境要求

- Python 3.11-3.13
- Windows 10/11
- Git
- CMake
- Visual Studio Build Tools（可选，用于编译）

## 📝 注意事项

1. **路径配置**: 安装脚本硬编码安装到 `D:\Users\wh898\.unsloth\studio`，避免占用 C: 盘
2. **GPU 加速**: 需要安装 CUDA Toolkit 12.6 和 NVIDIA 显卡驱动
3. **环境变量**: `USERPROFILE` 保持不变（指向 C:），仅 Unsloth 安装在 D:
4. **符号链接**: 如遇到问题可创建符号链接：
```powershell
New-Item -ItemType SymbolicLink -Path "C:\Users\wh898\.unsloth" -Target "D:\Users\wh898\.unsloth" -Force
```

## 🔧 常见问题

### 启动失败

1. **检查虚拟环境**：
   ```powershell
   Test-Path "D:\Users\wh898\.unsloth\studio\unsloth_studio\Scripts\activate.bat"
   ```

2. **检查端口占用**：
   ```powershell
   netstat -ano | findstr :8888
   ```

3. **重新安装依赖**：
   ```powershell
   .\Unsloth-install.ps1
   ```

### 模型下载慢

使用 `download_model.py` 已自动配置国内镜像（hf-mirror.com）。

### CUDA 相关

确保 CUDA 12.6 已安装：
```powershell
nvcc --version
```

## 📄 许可证

本项目仅供个人学习和研究使用。

## 👤 作者

个人项目集合
