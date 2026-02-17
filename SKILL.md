---
name: long-runner-harness
description: "长时间运行 Agent 的自动化框架。基于 Anthropic 官方 autonomous-coding 模式，实现 Dual-Agent 架构 + Browser-First Testing + Defense-in-Depth Security。"
version: 4.0.0
source: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
reference: https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding
---

# Long-Runner Harness v4.0

基于 Anthropic 官方 autonomous-coding 模式，实现真正的长时间自动执行。

## 核心原则

> **每个功能必须在独立的新 session 中执行，避免上下文过长。**
> **每个功能必须通过真实浏览器 UI 验证（Playwright MCP），不得仅用 curl/单元测试。**

---

## 架构概览

### Dual-Agent 模式

参照 Anthropic 官方实现，两个 agent 本质上是同一系统的不同初始 prompt：

| Agent | 职责 | 触发时机 |
|-------|------|----------|
| **Initializer Agent** | 设置初始环境、创建 feature_list、编写 init.sh | 首次运行 (`/long-runner init`) |
| **Coding Agent** | 增量进展 + 浏览器验证 + 留下清晰 artifacts | 后续每次运行 (`/long-runner continue`) |

### 调度器架构

```
┌─────────────────────────────────────────────────────────────┐
│                  调度器 (Dispatcher)                         │
│  - 读取 feature_list.json                                   │
│  - 选择下一个功能（passes=false, deps satisfied）            │
│  - 启动新 claude session 执行                                │
│  - 等待完成，检查结果                                        │
│  - 错误时自动等待重试                                        │
│  - 循环直到全部完成或遇到阻塞                                │
└─────────────────────────────────────────────────────────────┘
           │
           │ claude --print -p "Coding Agent prompt..."
           │   --settings .claude_settings.json
           ▼
┌─────────────────────────────────────────────────────────────┐
│              子 Session (全新 context window)                │
│  1. 获取上下文 (pwd, progress, git log, feature_list)       │
│  2. 启动环境 (./init.sh)                                    │
│  3. 回归测试 (Playwright MCP 验证已通过功能)                 │
│  4. 实现功能 (代码 + 前后端)                                 │
│  5. 浏览器 UI 验证 (Playwright MCP, 截图存证)               │
│  6. 更新 feature_list.json (只改 passes 字段)               │
│  7. git commit                                               │
│  8. 更新 claude-progress.txt                                 │
│  9. 确保 session 结束时代码干净                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 核心失败模式与对策

来自 Anthropic 官方研究的四大失败模式：

| 问题 | Initializer Agent 行为 | Coding Agent 行为 |
|------|----------------------|-------------------|
| **过早宣布完成** | 创建详尽的 feature_list.json（50-200+ 功能） | 读取列表，逐个完成，检查剩余数量 |
| **留下半成品/bug** | 创建 git repo + progress 文件 | 每次启动读 progress+git log，结束时 commit+更新 |
| **标记完成但有 bug** | 设定 feature_list 不可变规则 | 必须通过浏览器 UI 端到端测试后才可标记 |
| **不知如何运行 app** | 编写 init.sh 启动脚本 | 启动时运行 init.sh |

---

## 安全模型（Defense-in-Depth）

参照官方 `security.py` 的三层防御架构：

### 第一层：OS 级沙箱
```json
{ "sandbox": { "enabled": true, "autoAllowBashIfSandboxed": true } }
```

### 第二层：文件系统隔离
文件操作限定在项目目录 `./**` 内，不可访问外部文件。

### 第三层：Bash 命令白名单
参照官方 `ALLOWED_COMMANDS`，只允许以下命令：

| 类别 | 允许的命令 |
|------|-----------|
| 文件检查 | `ls`, `cat`, `head`, `tail`, `wc`, `grep` |
| 文件操作 | `cp`, `mkdir`, `chmod +x` |
| 目录 | `pwd` |
| Node.js | `npm`, `node` |
| Python | `python`, `python3`, `pip` |
| 版本控制 | `git` |
| 进程管理 | `ps`, `lsof`, `sleep`, `pkill`（仅 dev 进程: node, npm, vite, next） |
| 脚本执行 | `./init.sh` |

**关键安全规则：**
- `pkill` 只允许杀 dev 进程（node, npm, npx, vite, next）
- `chmod` 只允许 `+x` 模式（使脚本可执行）
- 所有不在白名单内的命令将被拒绝

---

## feature_list.json 格式

**使用扁平 JSON 数组（不是 object 包裹）：**

```json
[
  {
    "id": "F001",
    "category": "functional",
    "priority": "high",
    "description": "New chat button creates a fresh conversation",
    "depends_on": [],
    "steps": [
      "Navigate to main interface",
      "Click the 'New Chat' button",
      "Verify a new conversation is created",
      "Check that chat area shows welcome state",
      "Verify conversation appears in sidebar"
    ],
    "passes": false
  },
  {
    "id": "F002",
    "category": "style",
    "description": "Chat input area has proper styling and placeholder",
    "depends_on": ["F001"],
    "steps": [
      "Navigate to chat page",
      "Take screenshot of input area",
      "Verify placeholder text is visible",
      "Verify input has proper border and padding"
    ],
    "passes": false
  }
]
```

**格式要求：**
- 扁平数组 `[{...}]`，不要用 `{"features": [...]}`
- 必须包含 `id`, `category`, `description`, `steps`, `passes` 字段
- `depends_on` 可选，用于声明功能依赖
- `priority` 可选 (`high`, `medium`, `low`)

**不可变规则（CATASTROPHIC INSTRUCTION）：**
- 绝不删除已有功能
- 绝不修改 description 或 steps
- 只允许修改 `passes` 字段：`false` -> `true`

---

## Playwright MCP 浏览器测试

**这是 v4.0 的核心升级。每个功能必须通过真实浏览器 UI 测试。**

### 为什么需要浏览器测试？

Anthropic 研究发现：即使提示 Claude 用 curl 或单元测试验证，它经常无法发现实际的 UI bug。只有通过真实浏览器自动化（像人类用户一样操作），才能有效发现端到端问题。

### Playwright MCP 工具清单

```
# 导航和页面控制
mcp__playwright__browser_navigate        导航到 URL
mcp__playwright__browser_snapshot        获取可访问性快照（优先于截图，用于操作决策）
mcp__playwright__browser_take_screenshot 截图保存（用于存证）
mcp__playwright__browser_resize          调整窗口大小（响应式测试）

# 用户交互
mcp__playwright__browser_click           点击元素
mcp__playwright__browser_type            输入文本
mcp__playwright__browser_fill_form       批量填写表单
mcp__playwright__browser_select_option   选择下拉选项
mcp__playwright__browser_press_key       按键操作
mcp__playwright__browser_hover           悬停元素
mcp__playwright__browser_drag            拖拽操作

# 等待和验证
mcp__playwright__browser_wait_for        等待条件满足
mcp__playwright__browser_console_messages 检查浏览器控制台错误
mcp__playwright__browser_evaluate        执行 JS（仅调试用）

# 标签页管理
mcp__playwright__browser_tabs            管理浏览器标签页
mcp__playwright__browser_close           关闭浏览器
```

### 测试规则

**必须做（DO）：**
- 在真实浏览器中导航到应用
- 像人类用户一样交互（点击、输入、滚动）
- 每步截图保存到 `evidence/` 目录
- 验证功能正确性和视觉外观
- 检查浏览器控制台是否有 JS 错误
- 验证完整的用户工作流

**禁止做（DON'T）：**
- 只用 curl 命令测试后端（后端测试不够）
- 使用 JS evaluate 绕过 UI（不走捷径）
- 跳过视觉验证
- 未经浏览器截图验证就标记 passes=true

### 回归测试 UI 检查清单

每次回归测试时，需要关注以下 UI 问题：
- 白色文字在白色背景上（对比度问题）
- 页面显示随机字符或乱码
- 时间戳不正确
- 布局溢出或错位
- 按钮间距过小
- 缺少 hover 状态
- 浏览器控制台有报错
- 响应式布局问题

### 已知限制

- browser-native `alert()` / `confirm()` 弹窗可能无法通过 MCP 正确捕获
- 依赖这些弹窗的功能可能需要额外的处理方式

---

## 错误恢复

### Session 内恢复
如果实现过程中代码出错且无法修复：

```bash
# 查看最近的正常提交
git log --oneline -10

# 恢复到上一个正常状态
git revert HEAD --no-edit

# 或者回退到特定提交
git checkout <commit-hash> -- <file>
```

### 调度器级恢复
- session 出错时（exit code != 0），调度器自动等待后重试
- 连续 3 次失败时，跳过该功能并记录到 notes 字段
- `Ctrl+C` 中断后，重新运行相同命令即可继续

---

## 命令行用法

```bash
# 初始化新项目
/long-runner init "构建一个 claude.ai 克隆"

# 单步执行（执行一个功能后暂停）
/long-runner continue

# 全自动执行（循环执行直到完成或阻塞）
/long-runner auto

# 批量执行（执行 N 个功能后暂停）
/long-runner auto --batch 5

# 查看进度
/long-runner status

# 测试特定功能
/long-runner test F001

# 从中断处恢复
/long-runner resume
```

---

## 与其他 skill 的整合

| 阶段 | 可整合的 skill | 作用 |
|------|---------------|------|
| 计划阶段 | `planner` agent | 为复杂功能生成实现计划 |
| 代码审查 | `code-reviewer` agent | 实现后自动审查代码质量 |
| 安全审查 | `security-reviewer` agent | 检查安全漏洞 |
| E2E 测试 | `e2e-runner` agent | 更复杂的 E2E 测试场景 |

---

## 最佳实践

1. **功能粒度要细** - 每个功能应该能在 1 个 session 内完成
2. **步骤要具体** - steps 应该是人类测试员能执行的明确指令
3. **及时提交** - 每完成一个功能就 commit，保持代码干净
4. **保留证据** - 浏览器测试截图保存在 `evidence/` 目录
5. **先修后建** - 回归测试发现问题时，先修复再实现新功能
6. **git 是安全网** - 出问题时用 git revert 而非手动修改
7. **一次一个** - 一个 session 只做一个功能，宁可少做也不要留下半成品
