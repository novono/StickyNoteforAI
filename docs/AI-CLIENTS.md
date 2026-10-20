# 在 Codex、Claude 和 Cursor 中使用贴贴

接好后，直接在 AI 对话里说“把这件事贴到桌面”即可。AI 会读取现有便签、选择分类、写下简短正文，把长背景放进展开后的详情。

先安装贴贴，再在常用的 AI 工具中添加一次本地 MCP 连接。贴贴本身不需要 API Key，AI 工具仍使用你原来的账户。

| 你使用的工具 | 接入入口 |
| --- | --- |
| Codex 桌面端 / CLI / IDE | [Codex 配置](#codex) |
| Claude Desktop | [桌面配置文件](#claude-desktop) |
| Claude Code | [CLI 添加命令](#claude-code) |
| Cursor | [用户级 mcp.json](#cursor) |

以下步骤用于**运行贴贴的同一台 Mac 上的本地 AI 会话**。远程 SSH、云端任务或另一台电脑不能通过这条本地路径操作你的 Mac 桌面；本项目没有远程 HTTP 服务。

## 先确认应用路径

按照 [README 的安装步骤](../README.md#在-mac-上运行)，从 DMG 将应用拖入“应用程序”，先成功打开一次。下面的配置默认使用 `/Applications/PaperMemory.app`。

在终端运行：

```sh
printf '{}' | /Applications/PaperMemory.app/Contents/MacOS/PaperMemory --cli health
```

出现 `"ok":true`、版本和数据目录，说明应用可用。这个命令只检查状态，不创建便签。

如果旧版放在个人目录 `~/Applications`，请继续使用实际位置，例如 `/Users/你的用户名/Applications/PaperMemory.app/Contents/MacOS/PaperMemory`。不要只填 `.app` 路径；要指向里面的可执行文件。

JSON / TOML 配置要使用**完整绝对路径**。默认安装的完整路径是：

```sh
/Applications/PaperMemory.app/Contents/MacOS/PaperMemory
```

## Codex

### 方式一：终端添加

已安装 Codex CLI 时运行：

```sh
codex mcp add paper-memory -- \
  /Applications/PaperMemory.app/Contents/MacOS/PaperMemory --mcp

codex mcp get paper-memory
```

检查显示的命令路径和 `--mcp` 参数。`get` 确认的是配置已存在，实际工具连接在会话中验证。

### 方式二：直接写配置

没有 CLI 时，在 `~/.codex/config.toml` 中合并下面一段；如果装在其他位置，请替换为实际绝对路径。已有 `paper-memory` 配置时更新原段，不重复添加：

```toml
[mcp_servers.paper-memory]
command = "/Applications/PaperMemory.app/Contents/MacOS/PaperMemory"
args = ["--mcp"]
```

保存后，重新打开 Codex 或开启新的本地会话。CLI 会话可以用 `/mcp` 查看连接；桌面端可直接发送下面的只读请求：

> 请调用 paper_context，告诉我现在有多少张活动便签、有哪些分类。先不要创建。

这两种方式选择一种即可。本机 Codex 客户端通过同一宿主的 MCP 配置接入；不要把 `mcpServers` JSON 整段贴进 TOML 文件。配置方式见 [OpenAI 官方 MCP 文档](https://developers.openai.com/codex/mcp)。

### 可选：安装使用规则

MCP 提供工具，Skill 补充“何时写、如何归类、冲突时如何处理”的规则。只配置 MCP 就能用。

若希望 Codex 始终能找到随项目提供的规则，在本仓库目录运行：

```sh
mkdir -p "$HOME/.agents/skills"
ditto skill "$HOME/.agents/skills/paper-memory"
```

新会话中可以说：

> 使用 paper-memory，把刚才确定的下一步贴到桌面。

如果旧版本的技能目录已经装过同名 skill，保留一个有效副本，避免重复出现。当前用户级技能位置依据 [OpenAI 官方 Skills 文档](https://developers.openai.com/codex/skills)。

## Claude Desktop

1. 打开 Mac 菜单栏中的 Claude → Settings → Developer → Edit Config。
2. 在 `~/Library/Application Support/Claude/claude_desktop_config.json` 中合并以下内容。如果装在其他位置，请修改应用路径；保留已有的其他服务器。
3. 完全退出并重新打开 Claude Desktop，再发送本页的只读验证请求。

```json
{
  "mcpServers": {
    "paper-memory": {
      "command": "/Applications/PaperMemory.app/Contents/MacOS/PaperMemory",
      "args": ["--mcp"]
    }
  }
}
```

此处连接的是本地程序，不是填写远程连接器 URL。菜单和配置位置依据 [MCP 官方本地服务器接入教程](https://modelcontextprotocol.io/docs/develop/connect-local-servers)。

## Claude Code

运行以下命令，将便签工具添加到个人范围，方便在不同项目里使用：

```sh
claude mcp add --transport stdio --scope user paper-memory -- \
  /Applications/PaperMemory.app/Contents/MacOS/PaperMemory --mcp

claude mcp get paper-memory
```

在 Claude Code 会话中用 `/mcp` 检查，再发送只读验证请求。`--` 后面是贴贴自己的命令和参数，不要省略。用户范围与命令格式见 [Claude Code 官方 MCP 文档](https://code.claude.com/docs/en/mcp)。

## Cursor

1. 打开或创建 `~/.cursor/mcp.json`，使用上方 **Claude Desktop 的同一段 JSON**，确认应用路径与实际安装位置一致。
2. 保留已有的 `mcpServers` 条目，只增加 `paper-memory`。
3. 重新加载 Cursor，在 Agent 会话中检查该工具已启用，再发送只读验证请求。

个人便签适合用户级配置；只想在一个项目使用时，可以改放 `.cursor/mcp.json`。配置位置和 stdio 格式依据 [Cursor 官方 MCP 文档](https://cursor.com/docs/mcp)。

## 第一次使用：确认它真的写到了桌面

先完成上面的只读检查，再发：

> 新建一张测试便签，正面两行：“接入成功”“试着直接编辑”；详情写“这张便签由 AI 创建，可以在纸上继续写”。请先参考已有分类。完成后读取它，核对内容。

桌面应出现新便签。你可以直接在小纸上修改，也可以点击右下角展开查看详情。最后告诉 AI：

> 把刚才这张测试便签收起来。

AI 应先获取最新修订号，再完成该便签；它会进入“已收起”，可恢复。工具可能显示客户端命名空间前缀，核心名称仍包含 `paper_context`、`paper_create`、`paper_get` 等。

## 平时怎么说

| 需求 | 可以直接发给 AI |
| --- | --- |
| 记下一步 | “把我们刚确定的下一步贴到桌面，正文不超过两行，背景放详情。” |
| 分开事项 | “把这三件独立的事分别做成便签，先检查有没有重复的。” |
| 自动归类 | “参考现有便签，按内容给这些事项归类，保留原文。” |
| 继续补充 | “给供应商交期那张便签补上刚才的结论，保留其他内容。” |
| 附上截图 | “把这个本地截图附在对应便签的详情里，保留已有图文。” |
| 查找 | “看看还有哪些客户跟进的便签，先不要修改。” |
| 完成 | “这件事处理好了，把对应便签收起来。” |
| 恢复 | “找到刚才收起的那张便签，恢复到桌面。” |

归类信息保存在背后，不会给纸面增加标题。截图需要 AI 能访问的真实本地图片路径；只在聊天里看得到图片、但没有本地文件时，可以先保存图片，或直接粘贴进展开的便签。

若内容来自飞书：让 AI 先通过已有的飞书工具读取，或把相关内容发给 AI，再要求写入贴贴。贴贴不会自行监听飞书。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| 首次打开被 macOS 阻止 | 先从“应用程序”打开一次，再按 [README 的首次打开说明](../README.md#在-mac-上运行) 处理；完成后再接入 AI。 |
| 找不到文件 / 无法启动服务器 | 先执行 `--cli health`；检查完整路径、安装位置，以及是否带了 `--mcp`。 |
| AI 说没有便签工具 | 新建本地会话或重启客户端，检查 MCP 是否启用；确认任务运行在这台 Mac，而非远程主机。 |
| JSON / TOML 报错 | 合并到原配置，不重复同名键；JSON 不能有注释或尾逗号，Codex 使用 TOML。 |
| 配置成功但没有出现在桌面 | 先打开贴贴；桌面模式位于普通窗口下方，查看桌面。再检查 MCP 和应用是否使用同一 `PAPER_MEMORY_HOME`。 |
| 写入提示版本冲突 | 让 AI 重新读取该便签，再合并修改；不要反复提交旧修订号。 |
| 正面放不下 | 缩短到 60 字、6 行以内，并适应当前字号；长内容放详情。 |
| 运行 `--mcp` 后终端没有输出 | 正常：它等待客户端发送协议消息。用 `--cli health` 检查安装，用 AI 客户端连接 MCP。 |
| 客户端询问是否运行工具 | 按客户端的工具权限提示处理，无需为贴贴全局关闭权限检查。 |

配置步骤于 2026-10-20 对照官方文档核对；Codex 命令参数另经本机 CLI 0.163.0 检查。项目验证套件覆盖 MCP 握手、工具发现及创建、更新、读取与冲突处理；Claude 和 Cursor 的说明依据官方配置格式，未在本机逐一登录验证。

需要字段、参数和返回值时，继续阅读 [AI 接口参考](AI-INTEGRATION.md)。
