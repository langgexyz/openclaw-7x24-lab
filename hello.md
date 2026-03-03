# openclaw-7x24-lab Pipeline 简介

openclaw-7x24-lab 是一条全自动 Dev/Test pipeline，用来保证仓库中的 Issue 能在全天候稳定推进。

## 状态机

```
new → ready → in-dev → in-test → ready-merge → done
```

## 状态说明

1. **new → ready**：Issue 创建后进入 `new`，需求确认后标记为 `ready`。
2. **ready → in-dev**：dev agent 领取 `ready` Issue，开始实现需求，开 PR。
3. **in-dev → in-test**：开发完成后，Issue 推进到 `in-test`，交由 test agent 验证。
4. **in-test → ready-merge**：测试通过，状态切换为 `ready-merge`，触发自动合并。
5. **ready-merge → done**：PR 合并后，Issue 自动关闭并标记为 `done`。

失败路径：任何阶段失败均标记为 `blocked`，需人工介入。
