# Long-Runner Harness Command

长时间运行 Agent 的自动化框架，基于 Anthropic 官方最佳实践。

**v5.2: Browser-First Testing + Defense-in-Depth Security + Error Recovery + Smoke-Test Gate + External Validation**

> 参考来源: [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
> 代码库: [claude-quickstarts/autonomous-coding](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding)

> v5.0 新增（基于 Meta-Harness 论文 arxiv:2603.28052v1）:
> - **Bootstrap 快照**: 自动探测项目环境，消除每轮 2-3 次探索浪费
>
> v5.2 架构优化:
> - **简化存储**: 去掉 6 类 trace 文件，回归 `claude-progress.txt + git log` 极简模式；保留 `.lr-bootstrap/` 环境快照
> - **固定冒烟测试**: init 生成 `smoke-test.sh`，每个 session 在 STEP 2.5 强制先跑，确保 app 不被回退破坏
> - **调度器外部验证**: session exit 0 后验证 passes 是否真的增加，防止"假成功"累积

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
| 方案/需求质量不足 | **双 Agent 辩论：提案者 + 评审者** | 读取经过辩论审查的 feature_list |

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
├── smoke-test.sh          # 固定冒烟测试（每个 session 开始前必须通过）
├── claude-progress.txt    # 进度日志（每个 session 追加，格式见下方）
├── app_spec.txt           # 项目规格说明
├── .claude_settings.json  # 自动化权限配置
├── evidence/              # 浏览器测试截图证据
├── docs/plans/            # 实现计划
└── .lr-bootstrap/
    └── env-snapshot.json  # 自动生成的环境快照（bootstrap）
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
| 脚本执行 | `./init.sh`, `./smoke-test.sh` |

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
      "Bash(./smoke-test.sh)",
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
      "Bash(curl:*)",
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

**STEP 2.5: 初始化 Bootstrap 快照目录**

```bash
mkdir -p .lr-bootstrap
```

（环境快照会由调度器自动生成到 `.lr-bootstrap/env-snapshot.json`，init 阶段无需手动填写）

**STEP 3: 创建 app_spec.txt**

根据用户描述，生成详细的项目规格说明，包括：
- 技术栈选择
- 功能需求列表
- API 端点设计
- 数据模型
- UI/UX 规范

**STEP 3.5: 双 Agent 辩论（技术方案 + Feature List 审查）**

基于 app_spec.txt，启动两个并行的 Agent 进行辩论式协作。**这是提升 feature_list 质量的关键步骤，不得跳过。**

**Agent A（提案者 / Proposer）**：

**必须先调用 superpowers:brainstorm skill 进行技术方案头脑风暴，再生成 feature_list。**

如果 brainstorm skill 可用，Agent A 的执行流程为：
1. 调用 `superpowers:brainstorm` skill，输入项目描述 + app_spec.txt 内容
2. 从 brainstorm 输出中提炼技术方案（选择技术栈、说明理由、列出替代方案）
3. 基于头脑风暴结果生成 feature_list.json

如果 brainstorm skill 不可用，回退到直接生成。

Agent A 的 Prompt 要点：
```
你是一个全栈架构师。基于以下 app_spec.txt，完成两项任务：

1. 先调用 superpowers:brainstorm skill，对项目进行技术方案头脑风暴
   - 将 app_spec.txt 的完整内容作为 brainstorm 的输入
   - 从 brainstorm 结果中提炼最终技术方案
   - 选择技术栈，说明理由，列出替代方案及为什么没选

2. 基于头脑风暴结果，生成完整 feature_list.json：至少 50 个功能测试

要求：
- 扁平 JSON 数组格式
- 包含 functional 和 style 两类
- 混合简短测试（2-5步）和综合测试（10+步），至少 25% 需要 10+ 步
- 每个功能的 depends_on 必须准确反映真实依赖
- 按优先级排序：基础功能优先
- 所有 passes=false

输出格式：
## 技术方案（基于 brainstorm）
[方案描述]

## feature_list.json
[完整 JSON]
```

将 app_spec.txt 的完整内容附在 prompt 末尾。

**Agent B（评审者 / Critic）**：

Prompt 要点：
```
你是一个资深技术评审专家。你的职责是挑战和改进技术方案。

你将收到一份 app_spec.txt 和一份技术方案 + feature_list 的初稿。
请从以下角度进行严格审查：

1. 技术方案审查：
   - 是否过度设计？有没有更简单的方案？
   - 是否考虑了性能、安全、可维护性？
   - 依赖关系是否合理？

2. feature_list 审查（重点！）：
   - 有没有遗漏的关键功能？（用户认证的边界情况、错误处理、加载状态等）
   - 步骤是否足够具体可执行？（"验证页面正常" 不合格，必须写明验证什么）
   - depends_on 依赖关系是否正确？（有没有循环依赖或遗漏？）
   - 优先级排序是否合理？
   - 边界情况和错误路径有没有覆盖？

3. 补充建议：
   - 列出你认为缺失的 feature，按优先级排列
   - 列出你认为步骤不够清晰的 feature，给出改进建议
   - 列出你认为依赖关系有问题的 feature

输出格式：
## 技术方案评审
[评审意见]

## Feature List 评审
### 遗漏的功能
[列表]

### 步骤不够清晰的 Feature
[列表]

### 依赖关系问题
[列表]

## 建议新增的 Feature
[完整 JSON 数组，包含 id（从当前最大 id+1 开始）、category、priority、description、depends_on、steps、passes=false]
```

将 app_spec.txt + Agent A 的完整输出附在 prompt 末尾。

**执行方式**：

使用 Agent 工具并行启动 A 和 B：

```
Agent A: "proposer" - General-Purpose 类型，传入 app_spec.txt
Agent B: "critic"   - General-Purpose 类型，传入 app_spec.txt
```

**如果项目较小（用户描述明显是简单应用）**，可以串行执行：先 A 后 B。

**STEP 4: 综合辩论结果，生成最终 feature_list.json**

收到两个 Agent 的输出后，主线程负责综合：

1. 读取 Agent A 的技术方案和 feature_list 初稿
2. 读取 Agent B 的评审意见和补充建议
3. 综合决策：
   - 技术方案：采纳合理的质疑，保留有充分理由的选择
   - feature_list：合并 A 的初稿 + B 建议新增的 feature（去重）
   - 对 B 指出"步骤不够清晰"的 feature，补充完善步骤
   - 对 B 指出"依赖关系问题"的 feature，修正 depends_on
4. 写入最终 feature_list.json

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

**最终 feature_list 要求：**
- 最少 50 个功能测试（复杂项目 200+）
- 包含 "functional" 和 "style" 两类
- 混合简短测试（2-5步）和综合测试（10+步）
- 至少 25% 的测试需要有 10+ 步
- 按优先级排序：基础功能优先
- **所有测试初始 passes=false**
- 已经过 Agent B 审查，覆盖边界情况和错误路径

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

**STEP 5.5: 创建 smoke-test.sh**

`smoke-test.sh` 是每个 coding session 开始时的最小化冒烟测试，确保 app 没有被上次 session 破坏。

```bash
#!/bin/bash
# smoke-test.sh — 固定冒烟测试
# 每个 coding session 在 STEP 2.5 运行，确保 app 处于可工作状态
# 失败时 exit 1，成功时 exit 0，必须在 30 秒内完成

set -e
echo "Running smoke test..."

# 1. 检查服务进程是否运行（根据项目实际情况调整）
# if ! pgrep -f "node\|npm\|python" > /dev/null 2>&1; then
#   echo "FAIL: No dev server process found."
#   exit 1
# fi

# 2. 检查应用主页可访问（根据实际端口调整）
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" != "200" ]; then
  echo "FAIL: App not responding (HTTP $HTTP_STATUS). Expected 200."
  exit 1
fi

echo "Smoke test PASSED (HTTP $HTTP_STATUS)"
exit 0
```

**要求**：
- 必须在 30 秒内完成
- 失败时 `exit 1`，成功时 `exit 0`
- 输出要清晰（PASS/FAIL + 原因）
- 根据项目实际情况调整检测逻辑

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

**STEP 8.5: 生成环境 Bootstrap**

Initializer agent 需要探测项目环境并写入 `.lr-bootstrap/env-snapshot.json`，包含：

```json
{
  "os": "检测到的操作系统",
  "package_manager": "npm / pip / cargo / 其他",
  "language_version": "Node.js / Python 版本",
  "framework": "检测到的框架（如有）",
  "dev_command": "启动开发服务器的命令",
  "port": 3000,
  "database": "检测到的数据库（如有）",
  "generated_at": "ISO-8601 时间戳"
}
```

探测方式：检查 `package.json`、`requirements.txt`、`Cargo.toml`、`go.mod` 等文件，运行 `node --version`、`python3 --version` 等命令收集信息。

如果 session 还有余量，可以开始实现最高优先级的功能。记住：一次只做一个功能。

---

### 模式: continue - 继续开发（Coding Agent）

**每个功能在独立 Session 执行，全新 context window，无之前记忆。**

**STEP 1: 获取上下文（MANDATORY - 必须最先执行）**

```bash
# 如果 bootstrap 存在，读环境快照（1 条命令替代原来的 7 条）
if [ -f .lr-bootstrap/env-snapshot.json ]; then
    cat .lr-bootstrap/env-snapshot.json
else
    # 回退到 v1 探索
    pwd && ls -la && cat app_spec.txt && cat feature_list.json | head -50
fi
```

无论哪种路径，仍需读取以下文件获取完整上下文：
```bash
cat claude-progress.txt
git log --oneline -20
cat feature_list.json | grep '"passes": false' | wc -l
```

**理解 app_spec.txt 是关键** - 它包含了应用的完整需求。

**STEP 2: 启动环境**

```bash
chmod +x init.sh
./init.sh
```

如果 init.sh 不存在，手动启动服务并记录过程。

**STEP 2.5: 冒烟测试门控（MANDATORY GATE）**

在做任何新功能之前，运行固定冒烟测试：

```bash
if [ -f smoke-test.sh ]; then
  chmod +x smoke-test.sh
  ./smoke-test.sh
  if [ $? -ne 0 ]; then
    echo "SMOKE TEST FAILED: App is broken. Fix before implementing new features."
    # Find what broke it using git log and fix it
  fi
fi
```

**如果冒烟测试失败**，说明上个 session 破坏了 app：
1. 用 `git log --oneline -5` 找到可能的罪魁祸首
2. 修复问题，确保冒烟测试通过
3. 再开始新功能

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

使用 Playwright MCP 工具集（完整列表见下方 Playwright 章节），像真实用户一样测试：

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

**STEP 9: 更新进度文件（claude-progress.txt）**

追加一条结构化记录：

```
## Session N — YYYY-MM-DD — Feature F001
- Status: completed | failed | partial
- Changes: src/auth.ts, app/login/page.tsx
- Regression: F002 ✅, F003 ✅
- Smoke-test: ✅
- Issues: none
- Hypothesis: {因果分析（如果调试过），或 "none"}
- Metrics: 12/50 features
- Next: F002 — 用户注册表单验证
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

**调度器外部验证层（v5.2 新增）：**
调度器在每个 session 完成后，**独立验证** feature_list.json 中 passes 数量是否实际增加：
- 若增加 → session 计为成功，进入下一个 feature
- 若未增加（假成功）→ 计入失败次数，重试该 feature
- 确保即使 `claude` exit 0 但 Agent 没有实际完成任何功能的情况也会被捕获

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

1. `browser_navigate` -> 打开应用 URL
2. `browser_snapshot` -> 获取页面结构（用 ref 选择元素）
3. `browser_click` / `browser_type` -> 交互操作
4. `browser_wait_for` -> 等待结果出现
5. `browser_take_screenshot` -> 保存到 `evidence/{feature_id}.png`
6. `browser_console_messages` -> 检查 JS 错误

### 注意事项

- 使用 snapshot（不是截图）来决定操作，它返回精确的 element ref
- 每步操作前先 snapshot，页面可能已变化
- 截图用于存证，保存到 `evidence/`
- 检查控制台错误：功能可能"看起来"正常但有 JS 报错
- 已知限制：browser-native alert/confirm 弹窗可能无法正确捕获

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
