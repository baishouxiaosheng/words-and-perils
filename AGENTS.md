# Words and Perils 开发入口

开工前读取 [开发操作规范](docs/development/WORKFLOW.md)，按其中的任务绑定、环境选择、测试分层和交接要求执行。

- 每个任务固定源码 commit、输入清单、范围和唯一 owner；共享文件和 main 发布由协调者串行管理。
- 本文件是工程协作约定，不授予新权限，不替代平台审批、引擎 guard 或可信队列协议。
- `coordination/local-work/` 的可信队列覆盖获准的独立 Raw / Natural 存档任务，以及所有者已明确接受的界面显示、状态和交互聚焦测试；聚焦测试仅限独立副本、headless Small。按[锁定协议](coordination/local-work/PROTOCOL.json)、[任务 Schema](coordination/local-work/TASK_SCHEMA.json)及[本地范围接受回读](coordination/local-work/results/LOCAL-QUEUE-BOOTSTRAP-20261008/scope-extension-20261009-bc788677/artifacts/ACCEPTANCE.json)执行，不含自动 Main、full GUI、full-game、FPS、live-model 或正式采用；本文不扩展权限、不改固定 hash。
- 源码候选、实际运行证据和正式采用分别记录。上传候选不等于采用；保持根 `README.md` 空白，不改仓库可见性或历史。
- 当前工作和执行状态以所有者指定的唯一共同总计划及本任务真实结果为准，不从历史启动文案推断，也不在本文件复制状态快照。公开仓库不得包含私有计划 URL、私人任务 metadata、密钥、个人信息或真实玩家档。
