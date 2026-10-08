# Words and Perils 本地测试交付

本轮明确范围已执行：Natural 四项空对象、Raw 十个场景、Natural 两种配方的完整 adapter。全部通过结果均绑定源码；原 Natural 测试的三处类型推断错误及失败回执保留，测试修复只在新可弃副本应用。候选独立，正式 v30 保持。

| 检查 | 真实结果 | Godot PID | 秒 | Job 提交峰值 MiB |
|---|---|---:|---:|---:|
| natural-compile-01 | 4/4 | 60220 | 1.5821 | 92.18 |
| raw-short-write-01 | 10/10 场景，57 断言 | 69328 | 1.3502 | 231.71 |
| natural-adapter-coastal-01 | 解析失败，运行用例 0 | 50284 | 0.2486 | 50.32 |
| natural-adapter-coastal-fixed-02 | 170 项，T03 13/13 | 64092 | 31.1755 | 155.84 |
| natural-adapter-plateau-fixed-01 | 170 项，T03 13/13 | 70340 | 28.5655 | 153.80 |

通过的四组均退出 0，stderr 为空，无 Godot ERROR/WARNING；Job 为空、Reader 完成、记录的进程句柄和守卫宿主退出。峰值为内核 Job 的提交内存，不是任务物理 RSS。守卫每次在新 PowerShell 核 SHA 并编译，Small 1 GiB、120 秒、64 KiB 合计输出、512 MiB 预留保持，无守卫故障注入。

Raw 的 7 项内存后端场景和 3 项真实隔离文件场景分列；没有验证实际磁盘短写、断电或崩溃耐久。Natural 每配方新增 13 项 T03 均逐项输出 passed；运行前后 traversal_policy.gd 和全复制文件 SHA 一致。测试入口继承原脚本，先核双 API 隔离路径，再执行原测试；观察器只记录 T03 断言，原测试断言逻辑不改。

修复差异只有测试脚本三处 `:=` 改为 `: Dictionary =`。原测试 SHA 为 99d750960ed2ba6197b5e624044a31276accd78c32aea78e000661179d2c66df；修复 SHA 为 60e46a3b5b607d3ba5cbe3634ebcd6bd3ebbfc98fa10d4bad8732ea95b5a0ba2。Natural 两份生产源码及 Raw 生产源码保持原候选 SHA，旧 manifest 没有修改。

public-v30 project.godot 的 SHA 为 34343acc9519c5479f0c0e86028fa7ed47bf207147d43a804c71ab504358c1fd；Raw 旧清单仍指向 0b35574f45a5b50307636bb3eee790a9c99be785ce3dc30c2b44e1c666dc0038。本次只验 public-v30 候选范围，不冒称旧私有分发全匹配。

8,136 个原有非 Git 文件已建立路径、大小和 SHA 索引，并终核全部保持。public-input、public-v30、原候选、原 74、Play、真实存档及原探针不改。总计划读取第 108 次更新，继续维护原链接，不另建总计划。先前 dot 连接聊天处于 idle；本轮直接本机执行，没有通过该聊天派发或消息协调。

原探针回执 82,571 字节及 SHA 7588f7eee645f386f03275405dba30927fac8b99e388c1d3af1e3868214641e9 保持。19 个回执绑定文件重新核 SHA 全同，两 API 同路径，marker SHA 2a55e35151a6d5685c6de1a66a051221185ebd1d9e111e68696f859ba9f806cc 匹配，路径拒绝与 return 均在写入前。独立勘误将运行北京时间记为 18:49:33.6029581 至 18:49:34.3005407；原 UTC 和回执不改。版本与 probe 均未重跑。

首次证据整理、过早启动器和证据后处理的工具错误另有记录；过早启动器未找到 SPEC，发生于 Godot 创建前。Natural 原测试失败和定点解析诊断均保留，不被通过结果覆盖。

未执行 Main、UI 整版、性能、真实模型、玩家完整旅程或正式采用。现有 v3 必须 headless，尚未录制图形功能视频；没有放松守卫启动图形进程。模型请求为 gpt-6.1-sol，但当前工具未暴露模型身份/切换接口，因此未把模型切换记为已验证。

下一项开发优先补 T03 共享 `.tmp`、并发写入与检查后目标变化的覆盖保护，另建候选和确定性竞争用例。Raw/Natural 合成仍须独立身份与测试闭环。本轮未重试 Library 403 或此前取消/拒绝的发布动作。
