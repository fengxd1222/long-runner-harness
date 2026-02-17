# Long-Runner Harness Command

长时间运行 Agent 的自动化框架，基于 Anthropic 官方最佳实践。

**v4.0: Browser-First Testing + Defense-in-Depth Security + Error Recovery**

> 参考来源: [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
> 代码库: [claude-quickstarts/autonomous-coding](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding)

---

## 核心设计原则

基于 Anthropic 官方研究，长时程 Agent 面临的核心挑战和解决方案：

| 失败模式 | Initializer Agent 行为 | Coding Agent 行为 |
|---------|----------------------|-------------------|
| 过早宣布完成 | 创建 feature_list.json 详尽功能列表 | 读取列表，逐个完成，不得跳过 |
| 留下未记录的 bug | 创建 git repo + progress 文件 | 启动时读取进度+git log，结束时提交+更新 |
| 功能标记过早 | 设定 feature_list 规则 | 必须通过浏览器 UI 自动化验证后才可标记 |
| 环境启动困难 | 编写 init.sh 标准化启动 | 启动时运行 init.sh |
| 上下文过长导致遗忘 | 设定 session 隔离架构 | 每个功能在独立 session 执行 |

---

## 用法

```bash
/long-runner init "项目描述"     # 初始化新项目
/long-runner continue           # 继续开发（执行下一个功能）
/long-runner auto               # 全自动模式（循环执行直到完成）
/long-runner auto --batch 5     # 半自动模式（执行 5 个功能后暂停）
/long-runner status             # 查看进度
/long-runner test <feature_id>  # 测试特定功能
/long-runner resume             # 从中断处恢复
```

### 自动模式说明

| 模式 | 命令 | 行为 |
|------|------|------|
| 单步 | `/long-runner continue` | 执行 1 个功能后暂停 |
| 批量 | `/long-runner auto --batch N` | 执行 N 个功能后暂停 |
| 全自动 | `/long-runner auto` | 不停执行直到：全部完成 / 遇到阻塞 |

---

## 项目结构

```
project/
├── feature_list.json      # 功能列表（JSON 扁平数组，只允许修改 passes 字段）
├── init.sh                # 启动脚本（标准化环境启动）
├── claude-progress.txt    # 进度日志（每个 session 追加）
├── app_spec.txt           # 项目规格说明
├── .claude_settings.json  # 自动化权限配置
├── evidence/              # 浏览器测试截图证据
└── docs/plans/            # 实现计划
```

---

## 安全模型（Defense-in-Depth）

参照 Anthropic 官方 autonomous-coding 的三层防御架构：

### 第一层：OS 级沙箱
```json
"sandbox": { "enabled": true, "autoAllowBashIfSandboxed": true }
```

### 第二层：文件系统限制
文件操作限定在项目目录 `./**` 内。

### 第三层：Bash 命令白名单
只有以下命令被允许执行：

| 类别 | 允许的命令 |
|------|-----------|
| 文件检查 | `ls`, `cat`, `head`, `tail`, `wc`, `grep` |
| 文件操作 | `cp`, `mkdir`, `chmod +x` |
| 目录 | `pwd` |
| Node.js | `npm`, `node` |
| Python | `python`, `python3`, `pip` |
| 版本控制 | `git` |
| 进程管理 | `ps`, `lsof`, `sleep`, `pkill`（仅 dev 进程） |
| 脚本执行 | `./init.sh` |

**其他所有 bash 命令将被安全 hook 拒绝。**

### 创建 `.claude_settings.json`:

```json
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true
  },
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Read(./**)",
      "Write(./**)",
      "Edit(./**)",
      "Glob(./**)",
      "Grep(./**)",
      "Bash(npm:*)",
      "Bash(node:*)",
      "Bash(git:*)",
      "Bash(python:*)",
      "Bash(python3:*)",
      "Bash(pip:*)",
      "Bash(cargo:*)",
      "Bash(make:*)",
      "Bash(./init.sh)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(wc:*)",
      "Bash(grep:*)",
      "Bash(mkdir:*)",
      "Bash(cp:*)",
      "Bash(chmod:*)",
      "Bash(sleep:*)",
      "Bash(pwd)",
      "Bash(ps:*)",
      "Bash(lsof:*)",
      "Bash(pkill:*)",
      "mcp__playwright__*"
    ]
  }
}
```

---

## 执行流程

### 模式: init - 初始化项目（Initializer Agent）

当用户运行 `/long-runner init "描述"` 时：

**STEP 1: 读取项目规格**

先读取 `app_spec.txt`（如果已有），理解完整的项目需求。

**STEP 2: 创建项目结构**

```bash
mkdir -p project/{evidence,docs/plans}
touch project/{feature_list.json,init.sh,claude-progress.txt,app_spec.txt}
```

**STEP 3: 创建 app_spec.txt**

根据用户描述，生成详细的项目规格说明，包括：
- 技术栈选择
- 功能需求列表
- API 端点设计
- 数据模型
- UI/UX 规范

**STEP 4: 创建 feature_list.json（关键！）**

**格式：扁平 JSON 数组（不要用 object 包裹）**

```json
[
  {
    "id": "F001",
    "category": "functional",
    "priority": "high",
    "description": "详细的功能描述和测试验证点",
    "depends_on": [],
    "steps": [
      "Step 1: 导航到页面",
      "Step 2: 执行操作",
      "Step 3: 验证结果"
    ],
    "passes": false
  }
]
```

**要求：**
- 最少 50 个功能测试（复杂项目 200+）
- 包含 "functional" 和 "style" 两类
- 混合简短测试（2-5步）和综合测试（10+步）
- 至少 25% 的测试需要有 10+ 步
- 按优先级排序：基础功能优先
- **所有测试初始 passes=false**

**CATASTROPHIC INSTRUCTION: IT IS UNACCEPTABLE TO REMOVE OR EDIT FEATURES IN FUTURE SESSIONS.** Features can ONLY be marked as passing (change `"passes": false` to `"passes": true`). Never remove features, never edit descriptions, never modify testing steps. This ensures no functionality is missed.

**STEP 5: 创建 init.sh**

```bash
#!/bin/bash
# 自动生成的启动脚本
set -e

echo "Starting development environment..."

# 安装依赖
npm install 2>/dev/null || pip install -r requirements.txt 2>/dev/null

# 启动服务（后台运行）
npm run dev 2>/dev/null &
# 或: python app.py 2>/dev/null &

# 等待服务启动
sleep 5

# 验证服务可用
echo "Checking service availability..."
curl -s http://localhost:3000 > /dev/null 2>&1 && echo "Service is running at http://localhost:3000" || echo "Warning: Service may not be ready yet"

echo "Environment ready!"
```

**STEP 6: 创建 .claude_settings.json**

（见上方安全模型配置）

**STEP 7: 初始化 Git**

```bash
git init
git add .
git commit -m "chore: initialize long-runner harness

- feature_list.json: 50+ feature tests
- init.sh: environment setup
- app_spec.txt: project specification
- .claude_settings.json: automation permissions
"
```

**STEP 8: 创建初始进度文件**

```
# Project Progress Log

## Session 1 - [date] (Initializer Agent)
- Initialized project structure
- Created feature_list.json with N features
- Set up init.sh script
- Status: 0/N features complete
- Next: F001 - [description]
```

**STEP 9: （可选）开始实现**

如果 session 还有余量，可以开始实现最高优先级的功能。记住：一次只做一个功能。

---

### 模式: continue - 继续开发（Coding Agent）

**每个功能在独立 Session 执行，全新 context window，无之前记忆。**

**STEP 1: 获取上下文（MANDATORY - 必须最先执行）**

```bash
# 1. 确认工作目录
pwd

# 2. 查看项目结构
ls -la

# 3. 读取项目规格，了解在构建什么
cat app_spec.txt

# 4. 读取功能列表，了解所有工作
cat feature_list.json | head -50

# 5. 读取之前 session 的进度
cat claude-progress.txt

# 6. 查看最近的 git 提交
git log --oneline -20

# 7. 统计剩余工作量
cat feature_list.json | grep '"passes": false' | wc -l
```

**理解 app_spec.txt 是关键** - 它包含了应用的完整需求。

**STEP 2: 启动环境**

```bash
chmod +x init.sh
./init.sh
```

如果 init.sh 不存在，手动启动服务并记录过程。

**STEP 3: 回归验证测试（CRITICAL! 必须在新功能之前执行！）**

**之前的 session 可能引入了 bug。在实现任何新功能之前，你必须运行回归测试。**

选择 1-2 个已标记 `passes=true` 的核心功能，使用 Playwright MCP 进行浏览器 UI 验证：

1. 打开浏览器导航到应用
2. 按照功能的 steps 执行操作
3. 截图保存验证结果

**如果发现任何问题（功能性或视觉性），必须：**
- 立即将该功能标记为 `passes=false`
- 将问题添加到修复列表
- **先修复所有问题，再开始新功能**
- 需要检查的 UI 问题包括：
  - 白色文字在白色背景上（对比度问题）
  - 页面显示随机字符或乱码
  - 时间戳不正确
  - 布局溢出或错位
  - 按钮间距过小
  - 缺少 hover 状态
  - 浏览器控制台有报错
  - 响应式布局在不同尺寸下的表现

**STEP 4: 选择一个功能来实现**

从 feature_list.json 中选择：
- `passes=false`
- `depends_on` 全部已满足（对应功能的 passes=true）
- 最高优先级

**专注于在这个 session 中完美完成一个功能。** 如果只完成一个功能也没关系，后续的 session 会继续推进。

**STEP 5: 实现功能**

1. 编写代码（前端和/或后端）
2. 使用浏览器自动化手动测试（见 Step 6）
3. 修复发现的任何问题
4. 验证功能端到端可用

**STEP 6: 浏览器 UI 自动化验证（MANDATORY! 这是必须的！）**

**你必须通过真实的浏览器 UI 验证功能。这不是可选的。**

使用 Playwright MCP 工具集，像真实用户一样测试：

```
mcp__playwright__browser_navigate    - 导航到应用 URL
mcp__playwright__browser_snapshot    - 获取页面可访问性快照（优先于截图）
mcp__playwright__browser_click       - 点击元素
mcp__playwright__browser_type        - 输入文本
mcp__playwright__browser_fill_form   - 填写表单
mcp__playwright__browser_select_option - 选择下拉选项
mcp__playwright__browser_press_key   - 按键操作
mcp__playwright__browser_hover       - 悬停元素
mcp__playwright__browser_wait_for    - 等待条件满足
mcp__playwright__browser_take_screenshot - 截图保存到 evidence/
mcp__playwright__browser_evaluate    - 执行 JS（仅用于调试，不要用来绕过 UI）
mcp__playwright__browser_console_messages - 检查浏览器控制台错误
```

**必须做：**
- 在真实浏览器中导航到应用
- 像人类用户一样交互（鼠标点击、键盘输入、滚动）
- 每个关键步骤截图保存到 `evidence/` 目录
- 验证功能正确性和视觉外观
- 检查浏览器控制台是否有错误
- 验证完整的用户工作流端到端

**禁止做：**
- 只用 curl 命令测试后端接口（后端测试不足以验证功能）
- 使用 JavaScript evaluate 绕过 UI（不允许走捷径）
- 跳过视觉验证
- 未经浏览器截图验证就标记 passes=true

**STEP 7: 更新 feature_list.json（小心操作！）**

**你只能修改一个字段：`passes`**

经过浏览器截图验证后，修改：
```json
"passes": false  -->  "passes": true
```

**绝对禁止：**
- 删除测试
- 编辑测试描述
- 修改测试步骤
- 合并或重排序测试

**只有在浏览器截图验证后才能修改 passes 字段。**

**STEP 8: Git 提交**

```bash
git add .
git commit -m "feat: implement [feature name] - verified end-to-end

- Added [specific changes]
- Tested with Playwright browser automation
- Updated feature_list.json: marked [ID] as passing
- Screenshots saved in evidence/
"
```

**STEP 9: 更新进度文件**

```
## Session N - [date] (Coding Agent)
- Completed: F001 - [功能名]
- Regression test: verified F00X and F00Y still working
- Issues found and fixed: [list any]
- Tests passing: X/Y (Z%)
- Next priority: F002 - [description]
```

**STEP 10: 确保 Session 结束干净**

在 context 用完之前：
1. 提交所有可工作的代码
2. 更新 claude-progress.txt
3. 更新 feature_list.json（如果有测试验证通过）
4. 确保没有未提交的更改
5. 确保应用处于可工作状态（没有被破坏的功能）

**如果代码出了问题且无法修复，使用 git 恢复：**

```bash
# 查看最近的提交
git log --oneline -10

# 恢复到上一个正常状态
git revert HEAD --no-edit
```

---

### 模式: auto - 全自动执行

**使用调度器脚本，每个功能独立 Session**

执行调度器脚本 `~/.claude/scripts/long-runner-dispatch.sh`:

```bash
# 全自动
~/.claude/scripts/long-runner-dispatch.sh /path/to/project

# 批量模式（每次5个功能）
~/.claude/scripts/long-runner-dispatch.sh /path/to/project 5
```

调度器会为每个功能启动新的 claude session，传入详细的 Coding Agent prompt（包含完整的 10 步流程），并在 `logs/` 目录记录每个 session 的输出。

**Session 隔离好处：**
- 全新 context window，避免上下文过长
- 失败隔离，一个功能失败不影响其他
- 可恢复，中断后 `Ctrl+C` 后再次运行同样的命令即可继续

**终止条件：**
1. **全部完成** - 所有功能 passes=true
2. **遇到阻塞** - 依赖不满足
3. **批量限制** - 执行了 N 个功能
4. **用户中断** - Ctrl+C

**错误恢复：**
- 如果 session 出错（status != 0），调度器会自动等待后重试
- 阻塞原因记录到 feature_list.json 的 notes 字段
- 用户可以手动解决后继续 `/long-runner auto`

---

### 模式: status - 查看进度

```bash
cat feature_list.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
total = len(data)
passed = sum(1 for f in data if f.get('passes', False))
pct = (passed / total * 100) if total > 0 else 0
print(f'Progress: {passed}/{total} ({pct:.1f}%)')
print()
for f in data:
    status = 'V' if f.get('passes') else 'O'
    deps = f.get('depends_on', [])
    dep_str = f' [needs: {deps}]' if deps else ''
    print(f'  {status} {f[\"id\"]}: {f[\"description\"][:50]}{dep_str}')
"
```

---

### 模式: resume - 从中断恢复

如果执行中断，运行：

```bash
/long-runner resume
```

流程：
1. 读取 claude-progress.txt 确认最后状态
2. 检查 feature_list.json 确认未完成功能
3. 检查 git 状态确保代码干净
4. 继续执行 auto 模式

---

## Playwright MCP 浏览器测试（核心能力）

**这是 long-runner 区别于普通开发流程的关键。每个功能都必须经过真实浏览器 UI 验证。**

### 前置配置

确保已配置 Playwright MCP：

```bash
claude mcp add playwright -- npx @playwright/mcp@latest
```

### 完整工具列表

| 工具 | 用途 | 使用场景 |
|------|------|---------|
| `browser_navigate` | 导航到 URL | 打开应用、跳转页面 |
| `browser_snapshot` | 获取页面可访问性快照 | **优先使用**，比截图更适合操作决策 |
| `browser_take_screenshot` | 截图保存 | 保存证据到 evidence/ |
| `browser_click` | 点击元素 | 按钮、链接、菜单项 |
| `browser_type` | 输入文本 | 文本框、搜索框 |
| `browser_fill_form` | 批量填写表单 | 登录表单、注册表单 |
| `browser_select_option` | 选择下拉项 | 下拉菜单 |
| `browser_press_key` | 按键 | Enter、Escape、Tab |
| `browser_hover` | 悬停 | 验证 hover 状态 |
| `browser_wait_for` | 等待条件 | 等待加载完成、文字出现 |
| `browser_evaluate` | 执行 JS | **仅用于调试**，不要绕过 UI |
| `browser_console_messages` | 控制台消息 | 检查是否有 JS 错误 |
| `browser_tabs` | 标签页管理 | 多标签场景 |
| `browser_drag` | 拖拽操作 | 拖拽排序等交互 |
| `browser_resize` | 调整窗口大小 | 响应式测试 |

### 典型测试流程

```
1. browser_navigate -> 打开应用 URL
2. browser_snapshot -> 获取页面结构（用于选择正确的 ref）
3. browser_click -> 点击目标元素（使用 snapshot 中的 ref）
4. browser_type -> 输入文本
5. browser_wait_for -> 等待结果出现
6. browser_take_screenshot -> 保存截图到 evidence/{feature_id}.png
7. browser_console_messages -> 检查是否有 JS 错误
```

### 注意事项

- **使用 snapshot 而不是截图来决定操作**：snapshot 返回可访问性树，包含精确的 element ref
- **每步操作前先 snapshot**：页面可能因上一步操作而改变
- **截图用于存证**：保存到 `evidence/` 目录作为验证证据
- **检查控制台错误**：功能可能"看起来"正常但有 JS 报错
- **已知限制**：browser-native alert/confirm 弹窗可能无法正确捕获

---

## 关键约束

| 规则 | 说明 | 原因 |
|------|------|------|
| **禁止删除/修改测试** | 只能添加新测试 | 防止功能缺失或 bug 被掩盖 |
| **使用 JSON 而非 Markdown** | feature_list 用 JSON 扁平数组 | 模型更不容易意外修改 JSON |
| **每次只做一个功能** | 专注单一任务 | 避免 context 耗尽，留下半成品 |
| **Session 结束必须干净** | 代码可合并、无大 bug | 下一个 agent 能顺利接手 |
| **必须浏览器 UI 测试** | 用 Playwright MCP 真实浏览器 | curl/单元测试无法发现 UI bug |
| **只改 passes 字段** | feature_list.json 只改这一个字段 | 确保测试完整性 |
| **先修 bug 再做新功能** | 回归测试发现问题必须先修 | 防止问题累积 |
| **git 恢复而非硬改** | 出问题时用 git revert | 保持代码历史干净 |

---

## 参数

`$ARGUMENTS` 格式：
- `init "描述"` - 初始化新项目
- `continue` - 继续开发下一个功能
- `auto [--batch N]` - 全自动执行（可选批量限制）
- `status` - 显示进度
- `test <id>` - 测试指定功能
- `resume` - 从中断处恢复

---

## 参考资源

- [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [claude-quickstarts/autonomous-coding](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding)
- [Claude Agent SDK](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/sdk)
