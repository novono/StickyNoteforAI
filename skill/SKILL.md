---
name: paper-memory
description: 管理 Mac 桌面上的“贴贴”便利贴。当用户要求把对话中的临时待办、想法或截图贴到桌面，或整理、更新、完成已有便签时使用；支持多行短文本、详情、来源与按已有内容语义归类。
---

# 贴贴 · PaperMemory

每张便签是可直接书写、自动保存的独立 Mac 桌面窗口，固定 280×266 pt。正面最多 60 个字符、6 行，支持换行；详情最多 20,000 字。图片最多 12 张，单个导入文件最多 20 MB，导入后复制到本地。

优先使用已连接的 `paper_*` MCP 工具。没有加载 MCP 时使用本技能的 `scripts/paper-memory`，操作名作第一个参数，JSON 从 stdin 读取。该脚本会在写入后启动本地应用。不要直接编辑数据文件。

## 写入与归类

分类和来源是后台元数据，不显示在纸面上。详情在同一窗口内动画展开；图片与文本混排，选中文字可加删除线。

用户要求记录时，先调用 `paper_context`（CLI: `context`），阅读已有分类与相关便签。根据语义优先使用已有分类；没有合适分类时创建 1–16 字的简短分类。不要仅按关键词机械匹配。若可能重复，先检查已有内容再决定更新或新建。每个独立行动可单独一张；同一行动的要点可以多行。不要把整段聊天塞进正面。

创建字段：`summary`、`category`，可选 `details`、`sourceName`、`sourceURL`、`color`、`pinned`、`attachmentPaths`、`fontSize`、`fontStyle`。颜色 `butter/rose/sage/blue`。`fontSize` 可选 18、22、26，默认22。`fontStyle` 可选 `kai`（楷书）、`xing`（行书，默认）、`cao`（草书），中英文一起切换。`pinned:false` 贴在桌面层，`true` 浮在其他应用之上。仅使用真实的来源链接、已有本地截图和用户提供的内容。来源如“Codex”“飞书”“我”。用户只是聊天或问问题时，不自行建立便签。

例：用户说“把刚才飞书里供应商交期的事贴到桌面”，先读分类，再创建正面“确认供应商交期\n核对首批数量”，详情保存相关上下文，并附上实际可用的飞书来源链接。

## 编辑与整理

`get` / `list` 返回 `id` 与 `revision`。修改必须带 `expectedRevision`；有冲突时重新读取并合并用户意图，不覆盖新内容。

- `list`: 可选 `query`、`category`、`includeCompleted`。
- `get`: `id`。
- `update`: `id`、`expectedRevision`，加需要变更的字段；保留未指定内容。
- `attach`: `id`、`expectedRevision`、本地图片 `path`。
- `complete` / `restore`: `id`、`expectedRevision`；完成可恢复。
- `open`: `id`，打开详情窗口。
- `organize`: `assignments:[{id, expectedRevision, category}]`，一次最多 100 条，整个批次原子保存。用户要求整理时，基于已有正文与详情归类，不改动原文。读取数量不足时用 `list` 获取其余记录。

CLI 安全调用示例（文本通过 stdin，不拼接进 shell 命令）：

```python
import json, subprocess
from pathlib import Path
p = subprocess.run(
    [str(Path.home() / ".codex/skills/paper-memory/scripts/paper-memory"), "create"],
    input=json.dumps({"summary":"确认供应商交期\n核对首批数量", "category":"采购跟进", "sourceName":"Codex"}, ensure_ascii=False),
    text=True, capture_output=True, check=True)
print(p.stdout)
```

数据存放在 `~/Library/Application Support/PaperMemory`。AI 入口通过本机可执行文件直接运行，无网络服务端口。飞书内容由已有飞书工具读取或由用户提供，再写入此工具；本技能不自行监听聊天或设置定时任务。
