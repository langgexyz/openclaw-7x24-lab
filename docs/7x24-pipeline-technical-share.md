# 用 OpenClaw 搭建了一个 7x24 研发流水线

> 2026-03-03

我们想验证一个问题：**AI Agent 能否无人值守地完成从需求到代码合并的全流程？**

---

## 做了什么

用 OpenClaw 跑起来了一条全自动的研发流水线。在 GitHub 上提一个 Issue，打上 `ready` label，接下来的事情都交给 Agent：

1. **dev agent** 读需求、写代码、开 PR
2. **test agent** 验收、通过后自动合并
3. PR 合并后 Issue 自动关闭

全程不需要人点任何按钮。

---

## 状态机驱动

整个流程靠 GitHub label 的状态机推进：

```
new → ready → in-dev → in-test → ready-merge → done
```

每个 label 变化触发不同的 Agent 行为，状态本身就是锁，不会重复处理。

失败路径设计也很简单：逻辑错误或验收不通过 → `blocked`（需要人介入）；合并冲突 → 自动路由回 dev agent 做 rebase，不打扰人。

---

## 几个关键决策

**事件驱动，不轮询**

最开始的方案是 bash daemon 每 2 分钟轮询 GitHub。问题是没有任务时也在白白烧 token，一天 720 次空调用。

改成 GitHub Actions 监听 label 变化，有事件才触发，空转消耗为零。

**Agent 之间不直接通信**

dev agent 完成后改 label → `in-test`，test agent 监听这个 label 被动唤醒。Agent 之间完全解耦，谁挂了不影响另一个。

**消息类型区分职责**

Agent 收到三种消息：
- `[AUTO_DISPATCH]` → 实现需求
- `[AUTO_TEST]` → 验收
- `[AUTO_MERGE]` → 合并 PR

同一个 test agent，收到不同前缀的消息做不同的事，职责清晰。

**Commit 留下身份**

Agent 提交的代码会在 commit message 里标注模型信息：

```
Author: dev-agent(gpt-5.1-codex)

feat: add pipeline status script

Agent: dev-agent(gpt-5.1-codex)
Issue: #5
```

以后可以用 `git log --author="dev-agent"` 把所有 Agent 的提交过滤出来，也方便对比不同模型版本的表现。

---

## 穿透问题

OpenClaw 跑在本地，GitHub 无法直接调用。目前用 ngrok 临时解决：

```
GitHub Actions → ngrok → localhost:18789 → OpenClaw → Agent
```

免费 ngrok 域名会变，每次重启需要更新 GitHub Secret。后续计划做云端中继，固定域名打通。

---

## 实际效果

跑了两个真实需求验证：

- Issue #2：让 Agent 写一个 pipeline 说明文档 → PR 自动开、自动合并、Issue 自动关闭
- Issue #5：让 Agent 写一个查看流水线状态的 shell 脚本 → 同上，test agent 还真的执行了脚本验证输出格式

整个过程没有人工干预。

---

## 感受

这套东西本质上是在用 **「文字协议」替代「代码集成」**。Agent 之间的协作不靠 API 调用，靠 label 状态和消息前缀约定。

扩展起来也很简单，想加一个 code review agent，就在 `in-test` 之前插一个新状态，写几行 GitHub Actions 配置和一个角色指令文件就好了。

代码、配置、验证结果都在：[github.com/langgexyz/openclaw-7x24-lab](https://github.com/langgexyz/openclaw-7x24-lab)
