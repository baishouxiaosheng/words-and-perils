# WP-RAW-READBACK-VERIFY-20261009-003 — 可审阅、未采用

基线 `332a1f5f7025792d34e181f3e79690205498f5ab`；冻结输入 `8928d7012cb9c7cf42e1cb41f2717143299ebac9`；正式public-v30 host `e8ec5db0341f8b4a8aaa0a933e5968c33440c9da`。10项输入原字节数/SHA256/Git blob一致，2324项分层源码/资源（含876运行资源pin）核实。生产编辑0，Raw独立，001/002与旧Raw10/57成绩不转移或重跑。

新实际运行：先parse严格通过，再原始21个唯一场景全通过，195个断言。17项源码绑定内存场景、1项未就绪/no-I/O、3项native happy/open-failure分列；只新增允许的parse_entry/run_entry，原套件抽取/后端替换/断言不变。Engine SHA `f609fbf0bf717568c2429578bf4cde3eecf9a7aa806546c1d75c8dabdb0a4ef5`，save方法SHA `30cc3607de346361a8073dc689e8d957281f33cbebe7a79683a4c23f5e44bcc7`。两次Small v3守卫：无ERROR/WARNING，引擎/守卫/宿主退出0，Job/readers/记录句柄/宿主退出、双API隔离及源码前后map核验完成。主机原文件保留。

`BASELINE_VARIANT_PUBLIC_V30`：执行project34343acc…与Raw旧清单0b35574f…差异明确保留；不是完整旧清单匹配。输入扫描器README误判、发布脚本自包含凭据标记误判均保留，修正的是本地元数据处理，未改测试源码/断言，未重跑引擎。发布helper留本地，完整测试日志仍上传。

产物提交 `9d43f653a92d785738b6d905799b8508df2219a2`；ARTIFACTS SHA `c8b290969fbe64edb53c560f480cb04cb41c1d8d47443d31b399f40f048eb0ef`。75文件实际远端原字节读回匹配。首次TLS EOF失败后先只读核查，保留72个匹配返回，仅补读3个缺失项一次成功；不修改网络/凭据，不伪造上传结果。此独立结果提交再回读后写终态台账。

模拟flush/close/readback失效不等于真实磁盘短写、native flush/close失效、failed native rename保护、并发/CAS、fsync或崩溃/断电耐久。Job commit不冒充物理RSS或性能；source-binary绑定仍未建立。候选未采用，正式v30/README/Actions/历史/安全与真实存档不动。原生队列enabled=true；context unknown，compact unavailable。
