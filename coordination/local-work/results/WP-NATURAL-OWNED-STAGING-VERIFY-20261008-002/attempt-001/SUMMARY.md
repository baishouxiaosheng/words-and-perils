# WP-NATURAL-OWNED-STAGING-VERIFY-20261008-002 — 可审阅、未采用

源码基线 `e8941c2235069a168d9b6d92a0e9e1a62acce296`；生产 adapter SHA256 `7e11cf5a3679fdc3bee4aa4264a11ed49cdadb2744136c0ffb4bae2ee47fe345`。17 个输入及原 v3 守卫核实；生产修改 0，未组合 Raw、未采用正式 v30，任务001未重跑。

| 新实际运行 | 结果 |
| --- | --- |
| 独立 mkdir 语义探针 | 11 项严格通过 |
| 新候选 parse | 严格通过 |
| focused 五类写结果 | 90 断言严格通过 |
| owned-staging | 49 断言严格通过 |
| compile 空对象 | 4 项严格通过 |
| coastal_range 新入口 | 170 项，含13项T03，严格通过 |
| plateau_hinterland 新入口 | 170 项，含13项T03，严格通过 |
| 独立清理诊断 | 10 断言，观察到预期 ERROR；strict_pass=false，单独计数 |

所有运行均串行使用新副本/隔离数据/Small v3守卫。七套严格通过运行无 ERROR/WARNING；策略恢复、Job/readers/记录句柄/宿主退出及完整源码hash核验已完成。原8136文件不变。保留模拟故障与真实隔离 mkdir/UTF8 的区分，不宣称 OS 并发、目标CAS、外部替换保护、真实磁盘短写或崩溃耐久；原HTTP422/source-binary绑定未建立记录保留。

产物提交 `420016a61bba806e52d57b9321399e4a6f88becf`，205 文件逐项实际远端读回：字节数、SHA256、Git blob 全匹配。ARTIFACTS SHA256 `627af9627176a0712af1af290bedd9113406ff61c03e613bb733fc4320465145`。完整可读日志在本目录 evidence；新候选只含测试包装和绑定清单。

原生五分钟 heartbeat 已配置并实际投递两次，但均发生于活跃任务期间。第一次中断后旧锁持有进程退出；接续先调用持锁门禁的顺序误报被锁存，用户直接授权“恢复任务002发布”后先重新取得同一锁再仅完成发布。未重跑任何测试。automation_enabled=false：还须验证完成并空闲后实际定时唤醒及 canary/ACK。CLI canary 确有 worker、标记/UTC和exit0；既有配置警告和无关Figma AuthRequired原始诊断保留，非“零诊断通过”。需电脑唤醒、Codex app运行，不依赖dot执行连接；没有新增服务/开机启动/凭据/安全设置。
