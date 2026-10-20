# AI 接口

首次接入请先看 [Codex、Claude 和 Cursor 使用教程](AI-CLIENTS.md)，本页是开发者使用的工具与字段参考。

贴贴使用同一个可执行文件提供图形界面、MCP server 与 JSON CLI。数据保存在本机，接口不需要 API Key，也不启动 HTTP 服务。

## MCP

命令为应用内的 `Contents/MacOS/PaperMemory`，参数为 `--mcp`。传输使用 stdio，每行一个 JSON-RPC 消息。支持初始化、工具发现、调用和 ping；工具定义以运行时的 `tools/list` 为准。

| 工具 | 参数 | 用途 |
| --- | --- | --- |
| `paper_context` | 无 | 获取已有分类、最近更新的 100 张活动便签及总数 |
| `paper_list` | 可选 `query`、`category`、`includeCompleted` | 搜索、筛选、获取更多便签 |
| `paper_get` | `id` | 获取详情、附件文件信息与当前修订号 |
| `paper_create` | `summary`、`category`，以及可选内容字段 | 创建便签 |
| `paper_update` | `id`、`expectedRevision`，以及要修改的字段 | 更新指定字段 |
| `paper_complete` | `id`、`expectedRevision` | 移入已收起，可恢复 |
| `paper_restore` | `id`、`expectedRevision` | 恢复到桌面 |
| `paper_attach` | `id`、`expectedRevision`、`path` | 导入一张本地图片，保留已有富文本排版 |
| `paper_open` | `id` | 在原便签窗口展开详情 |
| `paper_organize` | `assignments` | 原子更新一批便签的分类 |

创建及更新的内容字段：

| 字段 | 约束 / 含义 |
| --- | --- |
| `summary` | 正面，最多 60 个字符、6 行 |
| `details` | 纯文本详情，最多 20,000 字 |
| `category` | 1–16 字；优先复用已有语义分类 |
| `sourceName` | 最多 40 字，如“飞书”“Codex”“我” |
| `sourceURL` | 实际可用的来源链接，最多 2,048 字符 |
| `color` | `butter`、`rose`、`sage`、`blue` |
| `pinned` | `true` 浮在窗口上方；`false` 放在桌面层 |
| `fontSize` | 18、22、26；默认 22 |
| `fontStyle` | `kai`、`xing`、`cao`；默认 `xing` |
| `attachmentPaths` | 仅创建时使用，最多 12 个本地图片路径 |

单个图片文件最多 20 MB，导入后复制进应用数据目录。后续追加图片使用 `paper_attach`。

## 推荐调用顺序

1. 用户明确要记录、更新或整理时，调用 `paper_context`；若超过 100 张，再用 `paper_list` 查询。
2. 判断是否已有同一事项。优先更新现有便签，或按独立事项创建；将长背景放进详情。
3. 根据内容选择分类。归类由调用方 AI 完成，应用只校验和保存结果。
4. 更新前获取最新 `revision`，作为 `expectedRevision` 传入。收到冲突时重新读取，再合并用户意图。

`update` 保留没有传入的字段。显式写入 `summary` 或 `details` 会替换相应纯文本并清除该部分既有富文本样式；只改分类或颜色时不要重复传正文。需要保留图文样式并追加图片时使用 `attach`。

批量归类示例：

```json
{
  "assignments": [
    {"id": "note-id-from-list", "expectedRevision": 3, "category": "采购跟进"},
    {"id": "another-note-id", "expectedRevision": 1, "category": "产品想法"}
  ]
}
```

一次 1–100 条；任一条冲突或不合法时，整批不保存。

## JSON CLI

操作名与 MCP 工具相同，去掉 `paper_` 前缀；另有只读的 `health` 用于检查版本和数据目录。JSON 参数从 stdin 读取，stdout 返回 `{"ok":true,"data":...}` 或 `{"ok":false,"error":"..."}`；失败退出码为 1。

在仓库目录检查构建：

```sh
printf '{}' | build/PaperMemory.app/Contents/MacOS/PaperMemory --cli health
printf '{}' | build/PaperMemory.app/Contents/MacOS/PaperMemory --cli context
```

用随附脚本创建便签，脚本会在写入成功后打开应用：

```sh
PAPER_MEMORY_APP="$PWD/build/PaperMemory.app" skill/scripts/paper-memory create <<'JSON'
{
  "summary": "确认供应商交期\n核对首批数量",
  "details": "在下一次采购沟通前核对交期与数量。",
  "category": "采购跟进",
  "sourceName": "我",
  "color": "butter",
  "pinned": false
}
JSON
```

原始 `--cli` 写入不会自动启动图形界面；MCP 和包装脚本会。`open` 返回的是展开请求已写入，并非界面已经完成动画的确认。

在程序中传递文本时，通过 stdin 发送 JSON，不将内容拼进 shell 命令：

```python
import json
import subprocess
from pathlib import Path

binary = Path.home() / "Applications/PaperMemory.app/Contents/MacOS/PaperMemory"
result = subprocess.run(
    [str(binary), "--cli", "list"],
    input=json.dumps({"query": "供应商"}, ensure_ascii=False),
    text=True,
    capture_output=True,
    check=True,
)
notes = json.loads(result.stdout)["data"]
```

## 环境与边界

| 环境变量 | 用途 |
| --- | --- |
| `PAPER_MEMORY_HOME` | 改用独立的数据目录 |
| `PAPER_MEMORY_NO_LAUNCH=1` | 禁止自动启动图形界面，供测试使用 |
| `PAPER_MEMORY_APP` | 包装脚本使用的应用路径，不是数据目录 |

正常使用时，让图形界面和 MCP 指向同一个数据目录。便签内容会作为工具结果提供给调用的 AI；应用本身没有后台模型，不主动读取其他应用的聊天。
