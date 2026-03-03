# 用 OpenClaw 搭建了一个 7x24 研发流水线

> 技术分享 · 2026-03-03

---

## 背景

我们想验证一个问题：**AI Agent 能否在无人值守的情况下，自主完成从需求到代码合并的全流程？**

`openclaw-7x24-lab` 就是这个验证项目。它不是一个功能产品，而是一条 **Agent 交付流水线的最小实现**，核心目标是让 dev agent 和 test agent 在 7x24 小时内自主处理 GitHub Issues。

---

## 整体架构

```
GitHub Issue (需求入口)
    ↓ label: ready
GitHub Actions (事件路由)
    ↓ curl POST /hooks/agent
ngrok tunnel
    ↓
OpenClaw Gateway :18789
    ↓ agentId: dev / test
Agent Session (GPT-5.1-Codex)
    ↓ gh CLI 操作
GitHub (PR / label / comment)
```

---

## 状态机

```
new → ready → in-dev → in-test → ready-merge → done
                 ↓          ↓          ↓
              blocked    blocked    in-dev (冲突时回退)
```

| 状态 | 触发动作 | 负责 Agent |
|------|---------|-----------|
| `new` | 人工确认后改为 `ready` | 人 |
| `ready` | 触发 `[AUTO_DISPATCH]` | dev agent |
| `in-dev` | 触发 `[AUTO_DISPATCH]`（含 PR 存在检查） | dev agent |
| `in-test` | 触发 `[AUTO_TEST]` | test agent |
| `ready-merge` | 触发 `[AUTO_MERGE]` | test agent |
| `done` | GitHub Actions PR 合并后自动关闭 | — |
| `blocked` | 需人工介入（逻辑失败、验收不通过） | 人 |

---

## 核心实现

### 1. 事件驱动，不轮询

原始方案是 bash daemon 每 2 分钟轮询 GitHub，问题明显：

- 没有任务时仍消耗 token（每天 720 次空调用）
- 并发处理复杂，需要外部锁机制

**最终方案：GitHub Actions + OpenClaw Webhook**

```
label 变化 → GitHub Actions 触发（毫秒级）→ curl /hooks/agent → agent 处理
```

空转 token 消耗为零，响应延迟从 2 分钟降到秒级。

### 2. GitHub Actions 路由层

`issue_state_machine.yml` 新增 `dispatch_agent` job，根据 label 决定调用哪个 agent、发什么消息：

```yaml
dispatch_agent:
  if: |
    github.event_name == 'issues' &&
    (github.event.label.name == 'ready' ||
     github.event.label.name == 'in-test' ||
     github.event.label.name == 'ready-merge')
  steps:
    - run: |
        if [ "$LABEL" = "ready" ]; then
          AGENT="dev"; MSG="[AUTO_DISPATCH]..."
        elif [ "$LABEL" = "in-test" ]; then
          AGENT="test"; MSG="[AUTO_TEST]..."
        else
          AGENT="test"; MSG="[AUTO_MERGE]..."
        fi
        curl -sf -X POST "${OPENCLAW_HOOK_URL}/hooks/agent" \
          -H "Authorization: Bearer ${OPENCLAW_HOOKS_TOKEN}" \
          -d "{\"agentId\":\"$AGENT\",\"message\":\"$MSG\"}"
```

### 3. OpenClaw Webhook 配置

`openclaw.json` 开启 webhook 接收：

```json
"hooks": {
  "enabled": true,
  "token": "${OPENCLAW_HOOKS_TOKEN}",
  "allowedAgentIds": ["dev", "test"]
}
```

`launchd` plist 注入 token 环境变量，gateway 重启后生效。

### 4. Agent 角色指令（共享 workspace + paths）

dev agent 和 test agent 共享同一个 workspace（`~/.openclaw/workspace`），但各自有专属角色文件：

```
workspace/
  AGENTS.md              ← 通用规则（所有 agent 都加载）
  roles/
    dev/AGENTS.md        ← dev 专属：实现需求、PR、label 流转
    test/AGENTS.md       ← test 专属：验收、合并、冲突路由
```

通过 `bootstrap-extra-files` hook 在 agent 启动时自动加载：

```json
"bootstrap-extra-files": {
  "enabled": true,
  "paths": ["roles/dev/AGENTS.md", "roles/test/AGENTS.md"]
}
```

agent 根据收到的消息前缀（`[AUTO_DISPATCH]` / `[AUTO_TEST]` / `[AUTO_MERGE]`）知道自己该做什么。

### 5. 三类 Agent 消息

| 消息类型 | 触发时机 | Agent 行为 |
|---------|---------|-----------|
| `[AUTO_DISPATCH]` | label: `ready` 或 `in-dev` | 检查是否有现存 PR → 实现或 rebase → 开/更新 PR → `in-test` |
| `[AUTO_TEST]` | label: `in-test` | 找 PR → 验收 → pass: `ready-merge` / fail: `blocked` |
| `[AUTO_MERGE]` | label: `ready-merge` | 找 PR → squash merge → done；冲突: `in-dev` |

### 6. Commit 身份追踪

每个 dev agent 的 commit 必须携带 agent 和模型信息：

```bash
git -c user.name="dev-agent(gpt-5.1-codex)" \
    -c user.email="langgexyz@users.noreply.github.com" \
    commit -m "feat: add pipeline status script

Closes #5
Agent: dev-agent(gpt-5.1-codex)
Issue: https://github.com/langgexyz/openclaw-7x24-lab/issues/5
Job-ID: 0ae1238a-6a92-4e93-96ed-7d0ddfc99776"
```

效果：
- `git log --author="dev-agent"` 快速过滤所有 agent 提交
- `git log --grep="Agent:"` 查看模型版本分布
- Job-ID 可关联具体 hook 调用

### 7. 冲突自动恢复（不走 blocked）

```
ready-merge → AUTO_MERGE → 发现冲突
  → 评论 "conflict detected, routing back to dev"
  → label: ready-merge → in-dev
  → GitHub Actions 触发 → dev agent AUTO_DISPATCH
  → dev agent 检测到已有 PR → rebase → push → in-test
  → test agent 重新验证 → ready-merge → 合并
```

`blocked` 只保留给需要人工判断的失败（逻辑错误、验收不通过），机械性冲突全自动解决。

---

## 本地穿透方案（ngrok）

OpenClaw Gateway 运行在本地 `localhost:18789`，GitHub 无法直接访问。临时方案：

```bash
ngrok http 18789
# → https://xxxx.ngrok-free.app
```

将 ngrok URL 存入 GitHub Secret `OPENCLAW_HOOK_URL`，GitHub Actions 通过 ngrok 调用本地 gateway。

**局限性：** ngrok 免费域名每次重启会变，需手动更新 Secret。

**未来方向：** OpenClaw 云端 Gateway 中继，固定域名 → 本地长连接转发。

---

## 验证结果

完整跑通了两个真实需求：

| Issue | 需求 | 结果 |
|-------|------|------|
| #2 | 创建 `hello.md` 文档 | PR #4 合并，issue 自动关闭 ✅ |
| #5 | 创建 `pipeline_status.sh` 脚本 | PR #6 合并，issue 自动关闭 ✅ |

验证了完整路径：
- ✅ label 事件驱动 agent 调度
- ✅ dev agent 自主实现需求并开 PR
- ✅ test agent 验收并自动合并
- ✅ 冲突检测后路由回 dev agent rebase
- ✅ commit 携带 agent + 模型身份信息
