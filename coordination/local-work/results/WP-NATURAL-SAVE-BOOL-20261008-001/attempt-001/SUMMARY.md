# WP-NATURAL-SAVE-BOOL-20261008-001 — 可审阅，未采用

修复 Natural `adapter.save_file` 忽略 `store_string` 返回值的问题：返回 false 或 flush 后可观察错误均在 rename 前失败，并关闭句柄。只改这一个生产文件，新增三个绑定实际 adapter 的测试文件；保留原 Natural identity engine 和三处 Dictionary 测试覆盖。

| 实际新运行 | 结果 |
| --- | --- |
| compile 空对象检查 | 4/4 |
| 五类写入结果 focused cases | 5 类、90 个断言；13 个准备断言 + 77 个场景断言 |
| coastal_range adapter | 170/170，确认其中 13 项 T03 执行 |
| plateau_hinterland adapter | 170/170，确认其中 13 项 T03 执行 |

四组通过运行均无 ERROR/WARNING，引擎/守卫/宿主退出码为 0。每套使用独立副本、双 API 隔离数据和新编译 v3 守卫；策略恢复、Job/Reader/记录句柄及宿主退出均核实。峰值为 Job commit 指标，未冒充测得物理 RSS 峰值。失败 focused 首跑（不合法的满体力 rest 准备动作）及修正后复测日志完整保留。日期自动解析造成的锁误报在启动配方回归前停止；用户直接授权“恢复这次首任务”后保持字符串日期比较并继续。

故障场景是确定性内存 I/O 模拟；Unicode UTF-8 成功还包含真实隔离文件写入和读回。不宣称验证真实磁盘短写、断电或崩溃耐久。

源码及完整证据提交：`e5745fbfd568415a5d8ca35ca25bd18d5a092e98`，167 个文件已按不可变提交实际远端读回，字节数、SHA-256、Git blob 全部匹配。ARTIFACTS.json SHA-256：`d77934e9acb94a8f1d8b1615f626d859d471bf829d7f33388f3f3cfe971f7254`。首次远端读回一次超时；只读核查后仅补读一个缺失文件，成功。Git push 的长路径 .gitattributes 警告已保留，随后全部文件实际字节匹配。

[候选源码](https://github.com/baishouxiaosheng/words-and-perils/tree/e5745fbfd568415a5d8ca35ca25bd18d5a092e98/candidates/t03-natural-write-result/wp-natural-save-bool-20261008-001) · [完整可读证据](https://github.com/baishouxiaosheng/words-and-perils/tree/e5745fbfd568415a5d8ca35ca25bd18d5a092e98/coordination/local-work/results/WP-NATURAL-SAVE-BOOL-20261008-001/attempt-001/evidence)

`automation_enabled=false`。仓库身份和当前 owner 写入权限已核实；未来获准写者名单与 dot 投递来源控制未建立（blocked_source_authentication）。本机 codex-cli 0.160.1 的 exec/resume 与原生调度接口可见，但无人值守权限和端到端 canary ACK 未验证（blocked_worker_entry）。没有安装或启动计划、服务、开机任务或创建密钥。下一优先项是补齐这两道未来 gate，再进行有边界的 canary；不自动处理未知后继任务。

原有 8136 个文件哈希未变，正式 v30、Raw、原74/Play、真实存档、README、队列控制及既有候选不动；本候选不等于采用。当前 context 百分比未知，无原生 compact 可调用；已写可恢复 checkpoint，不猜百分比。
