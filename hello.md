# 7x24 Pipeline Overview

`openclaw-7x24-lab` 负责演示和验证 7x24 自动派单流程。所有任务都会按照固定的状态机推进，确保交接清晰、测试充分。

## 状态机

```
new → ready → in-dev → in-test → ready-merge → done
```

## 状态说明
- **new**：任务刚创建，尚未有人领取。
- **ready**：任务已准备好，可由开发代理领取。
- **in-dev**：开发中，正在实现需求。
- **in-test**：实现完成并进入测试验证阶段。
- **ready-merge**：测试通过，等待合并和上线。
- **done**：PR 已合并，任务完全完成。
