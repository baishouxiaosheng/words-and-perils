# AI-GM 重建：独立可运行测试框架

这是 2026-10-02 根据已确认玩法决定新写的源码，不是找回丢失的新版源码。它与现有 v9/UI/离线 D20 协议并存，没有接入主场景、任何实时模型 API 或第三方模型进程。

## 实际运行

在 game 项目根目录：

```sh
mkdir -p /tmp/ai_gm_rebuilt/{data,config,cache}
XDG_DATA_HOME=/tmp/ai_gm_rebuilt/data \
XDG_CONFIG_HOME=/tmp/ai_gm_rebuilt/config \
XDG_CACHE_HOME=/tmp/ai_gm_rebuilt/cache \
godot --headless --path . --script res://tests/experimental/ai_gm_rebuilt/test_integration.gd
```

XDG 目录隔离解决当前云环境默认 HOME 不可写的 Godot 启动问题，不读取用户凭据或改变用户配置。结果写入 `artifacts/ai_gm_rebuilt/test_report.json`；运行输出保存于同目录的 `test_integration.log`。

12 个关键集成场景分别覆盖：

1. 默认生产 calculator 未配置时明确拒绝，不偷偷注入测试规则
2. 关注只读、空白文本不行动、明确玩家文字优先、行动关注冻结
3. 酒的位置/数量及活着的士兵数量从真实冻结 facts 派生数值
4. 伪 factref、私有 factref、非有限数、旧版本、换行动者、脚本字段与超深/循环输入拒绝
5. 未知 patch、非有限候选 patch 和重叠分支在掷骰前拒绝；合法方案冻结后不能改
6. 复合行动部分成功与直接判定，最终叙事只提供显示文本；失效叙事不阻断数值提交
7. 每个阶段的 JSON 保存/读取、真实 Godot RNG、一次性掷骰与重新载入前阶段的确定重放
8. 原子 staged commit、伪 token、篡改存档、重复提交、action counter 碰撞拒绝
9. 两个 actor/status 的稳定 ID 排序，保存字典换序后 decision hash 不变；poison/patrol 每回合只执行一次
10. 路径和可达范围共用 ground/flight/all/air 阻挡规则；倒树只改变地格状态
11. 仅换文字、新 action ID 或自然 turn+1 不能免费重试；真实资源/条件变化才开放新尝试
12. 固定测试故事锚、NPC 对话与秘密；明确单 secret allowlist、拒绝 saved policy 扩权、实际文件保存重载

## 核心接口

```gdscript
# 初始状态须满足 World.SCHEMA；没有 production rule 时只生成请求。
var gm = preload("res://core/ai_gm_rebuilt/engine.gd").new(initial_world)
var request = gm.begin_intent(player_text, exact_attention_reference)
# 默认 prepare_assessment 返回 NOT_CONFIGURED，不产生裁定或骰子。

# 只有测试代码显式注入 test_rule_a 和 fixture_resolver。
# 实际未来模型回复仍需满足 ai_gm_assessment/v1。
var prepared = gm.prepare_assessment(external_assessment_data)
var rolled = gm.roll_once(request.request.action_id)
var staged = gm.stage(request.request.action_id)
var narrator_request = gm.narration_request(request.request.action_id)
var display_text = gm.validate_narration_reply(external_narration_data)
# narrator 数据失败不能逆转结果、阻止 commit 或再掷骰。
var committed = gm.commit(request.request.action_id, staged.stage_hash)
```

`cancel_intent` 只允许取消尚未 resolved/roll 的意图元数据，不消耗 RNG、不推进回合、不删除已有 attempt/receipt 记录；已经 rolled/staged 的行动拒绝取消，纠正后的新意图须重新验证冻结事实。

`attention` 不创建行动；`state_copy`/`action_copy` 返回分离副本。`model_request` 只投影明确允许的冻结事实，不包含内部 RNG、receipt 或 pending/stage 数据。`narration_request` 投影既定公开结果/公开骰值/公开效果，且不会发送私有 flag patch；提交后仍可叙述历史记录。`validate_narration_reply` 只校验 schema/ID/version/context 与文本类型，不证明文本语义真实。将来的 UI 应单独显示 `authoritative_result`，不能让叙事覆盖它。

`save_data` 保存私有执行账本；它是内部存档，不是模型请求。载入必须使用与可信运行时完全相同的 disclosure policy；存档字段不能自行扩大 NPC secret 或 flag 共享权限。RNG 64 位 seed/state 用十进制字符串保存。普通 JSON 数值范围限制为 ±(2^53−1)，嵌套深度最多 64 层。

## 实际证据与未完成边界

本轮测试只证明程序完整性，不证明真实 AI 的语言理解、A/D/P 评分、certainty 判断或叙事诚实性。故事角色和回复是明确署名的 authored functional fixtures；不声称已经接上 AI 自动生成人物或实时交互。test_rule_a 的 1..10000 随机域只是基点测试演示，最终规则未选定；核心接受 calculator 提供的有限整数域，不锁定 D20/D100。

场景分层只有 stable scene/layer ID 框架；跨层详细地图和转换规则尚未实现。状态只有必要的 poison/flight/drunk 测试形状，patrol/status_tick 必须预配置才运行。没有扩成庞大状态规则书。

保存重放防止同一存档谱系正常 reload 免费重掷；没有宣称能阻止恶意编辑 JSON、故意分叉世界或回退外部未保存历史。生产 API、model credentials、用户的 6.1-sol low / 6.0-luna 未来偏好均未改变。

旧 v9 `test_core.gd` 54、`test_recorded_provider.gd` 14、`test_attention_core.gd` 112 断言也实际通过；旧 core/focus/relay/main 源文件 SHA-256 与开工前一致。这些是兼容回归结果，不累计到新框架的测试数量。
