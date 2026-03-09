# Claude Code Feishu Notify

将 Claude Code 的任务状态、提示词等信息推送到飞书群机器人。

## 功能特性

- 实时推送 Claude Code 任务状态到飞书
- 包含项目路径、最近提示词、任务进展等信息
- 支持多种 Hook 事件：任务完成、等待确认、通知等
- 支持中英文消息格式
- 配置简单，开箱即用

## 消息示例

```
【项目路径】
C:\Users\YourName\Projects\my-project
【提示词】
帮我创建一个用户登录功能
【CC任务进展】
Task Done
2026-03-09 08:30:00
```

## 快速开始

### 1. 创建飞书群机器人

1）.访问登录“创建飞书机器人”链接：https://botbuilder.feishu.cn/home/my-app
<img width="1587" height="327" alt="image" src="https://github.com/user-attachments/assets/d86addda-f0e5-4c5f-bea9-3b3ee34d3df4" />

2）. 在飞书官网，创建机器人应用流程：创建名称、创建流程
3）. 添加配置流程中第一个节点“Webhook触发”，配置内容如图所示，复制webhook链接，后面应用配置时会用到。
这里的参数配置为
```bash
{"msgtype":"text","content":{"text":"test"}}
```
<img width="1600" height="811" alt="image" src="https://github.com/user-attachments/assets/3ff44b72-920e-4c6a-a72b-6b69950fe051" />
   
4）. 配置流程的第二个节点“发送飞书消息”：配置消息内容时，点击“加号”按键添加变量，选择content.text

<img width="1600" height="820" alt="image" src="https://github.com/user-attachments/assets/a1897e2c-7a91-4b96-8d71-1f7f99c07456" />

5）. 发布机器人

### 2. 安装配置

```bash
# 克隆仓库
git clone https://github.com/your-username/claude-code-feishu-notify.git

# 进入目录
cd claude-code-feishu-notify

# 复制配置文件模板
cp config.example.json config.json

# 编辑配置文件，填入你的 Webhook 地址
# Windows: notepad config.json
# Mac/Linux: nano config.json
```

编辑 `config.json`：

```json
{
  "webhook_url": "https://www.feishu.cn/flow/api/trigger-webhook/你的webhook地址",
  "max_prompt_length": 100
}
```

### 3. 配置 Claude Code Hooks

编辑 Claude Code 的 settings.json 文件：

**Windows:** `C:\Users\你的用户名\.claude\settings.json`
**Mac/Linux:** `~/.claude/settings.json`

添加以下配置：

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File /path/to/claude-code-feishu-notify/feishu-notify.ps1"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File /path/to/claude-code-feishu-notify/feishu-notify.ps1"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File /path/to/claude-code-feishu-notify/feishu-notify.ps1"
          }
        ]
      }
    ]
  }
}
```

> **注意：** 请将 `/path/to/claude-code-feishu-notify` 替换为实际的安装路径。

### 4. 测试

重启 Claude Code，当任务完成或需要确认时，飞书群会收到通知消息。

## 配置说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `webhook_url` | 飞书机器人 Webhook 地址 | 必填 |
| `max_prompt_length` | 提示词最大显示长度 | 100 |

## 支持的 Hook 事件

| 事件 | 说明 |
|------|------|
| `Stop` | 任务执行完成 |
| `Notification` | 通知事件（如等待输入） |
| `PermissionRequest` | 需要用户确认 |
| `SessionEnd` | 会话结束 |
| `PostToolUse` | 工具使用后（如 AskUserQuestion） |

## 文件说明

```
claude-code-feishu-notify/
├── feishu-notify.ps1      # 主脚本
├── config.example.json    # 配置模板
├── config.json            # 你的配置（需自行创建，已忽略）
├── feishu-notify.log      # 运行日志（自动生成）
└── README.md              # 使用说明
```

## 安全提示

- `config.json` 包含你的 Webhook 地址，已在 `.gitignore` 中忽略
- 请勿将 `config.json` 提交到公开仓库
- 如需分享代码，请使用 `config.example.json` 作为模板

## 常见问题

### Q: 没有收到飞书消息？

1. 检查 `config.json` 中的 webhook_url 是否正确
2. 查看 `feishu-notify.log` 日志文件
3. 确认 Claude Code settings.json 中的脚本路径正确

### Q: 中文显示乱码？

确保脚本文件使用 UTF-8 编码保存。

### Q: Mac/Linux 如何使用？

脚本目前为 PowerShell 版本，Mac/Linux 用户可以使用 `pwsh` 命令运行，或自行转换为 Bash 脚本。

## License

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！
