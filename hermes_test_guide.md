# Hermes 功能测试指南

## ✅ 已配置的功能

### 1. **基础聊天功能**
- 模型：deepseek-v4-pro（通过 NVIDIA NIM）
- API Key：已配置（4个密钥轮换）
- 状态：✅ 可用

### 2. **Browser Automation（浏览器自动化）**
- 工具：agent-browser
- 安装方式：npm install -g agent-browser
- 状态：✅ 已安装

### 3. **Text-to-Speech（语音合成）**
- 提供商：Edge TTS
- 状态：✅ 已配置

### 4. **微信集成**
- Account ID: 53e9348d0518@im.bot
- 主频道：o9cq800tUhLK2mIFU3nE_5sh9M8A@im.wechat
- 状态：✅ 已配置

### 5. **终端命令执行**
- 后端：Local
- 状态：✅ 已启用

---

## 🧪 测试用例

### 测试 1：基础对话
```
你好，请介绍一下自己
```

### 测试 2：代码生成
```python
帮我写一个 Python 函数，计算斐波那契数列
```

### 测试 3：文件操作
```
在当前目录创建一个 test.txt 文件，写入"Hello Hermes"
```

### 测试 4：浏览器自动化
```
用浏览器打开 baidu.com
```

### 测试 5：任务规划
```
帮我规划一个学习 Python 的30天计划
```

### 测试 6：系统信息查询
```
查看当前系统的 Python 版本
```

---

## ⚠️ 暂时不可用的功能

### Web Search
- 原因：公共 SearXNG 实例连接不稳定
- 替代方案：手动提供信息或使用 Browser Automation

### Mixture of Agents
- 需要：OPENROUTER_API_KEY
- 状态：未配置

### Image Generation
- 需要：FAL_KEY 或 OPENAI_API_KEY
- 状态：未配置

---

## 🔧 常用命令

```powershell
# 启动聊天
hermes chat

# 查看配置
hermes config

# 检查状态
hermes doctor

# 启动网关（微信消息）
hermes gateway

# 查看网关状态
hermes gateway status

# 重新配置
hermes setup
```

---

## 📝 配置文件位置

- 主配置：`C:\Users\wh898\.hermes\config.yaml`
- API Keys：`C:\Users\wh898\.hermes\.env`
- 会话数据：`C:\Users\wh898\.hermes\sessions\`
- 日志：`C:\Users\wh898\.hermes\logs\`

---

## 💡 使用建议

1. **首次使用**：先在命令行测试基础功能
2. **微信使用**：确保网关服务运行（`hermes gateway`）
3. **遇到问题**：查看日志文件排查
4. **更新配置**：使用 `hermes setup` 或手动编辑配置文件

---

最后更新：2026-05-11
