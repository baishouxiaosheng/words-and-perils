独立格式器聚焦测试；源码已编写，GDScript 未 parse、未运行、未采用。发布以包含此目录的 Git 提交为准；STATIC_RESULT.json 的 NOT_UPLOADED 是检查时的历史发布状态，63/59 项仅为静态及 Python 准备检查。

绑定 INPUTS.json 中固定候选 commit、原 manifest 和 public-v30 文件哈希。source-input 是逐文件核过 final source map 的只读输入摘录，不是完整恢复项目；也可从现有 tools/restore_v30.py --sources-only 的正式恢复副本提供同源文件。prepare.py 不运行恢复器或引擎、不联网、不访问 user:// 或真实存档。

prepare.py --source-root SOURCE_ROOT --candidate-root CANDIDATE_ROOT --work-root AUTHORIZED_DISPOSABLE_ROOT --name UNIQUE_NAME
所有根必须已存在且不带 symlink。work-root 必须与输入及测试包互不包含；只创建新的直接子目录，已有目录一律拒绝，失败产物保留。全部 source/candidate/package pins 在创建副本前核完；source-root、candidate-root 仅只读。副本复制真实依赖、单个候选 overlay、未改的 baseline peer 和本测试入口，不合并另一候选，不复制生产 project.godot、Main、存档、.godot 或私人配置。

check_static.py --source-root SOURCE_ROOT --candidate-root CANDIDATE_ROOT
此入口用 Python 做哈希、覆盖源码、真实依赖类型与准备脚本回放；实际检查覆盖旧目录/路径穿越/重叠/symlink/改坏输入拒绝。不是 GDScript parser，也不执行测试断言。Linux 负例使用本任务可弃 /tmp 目录；Windows 如要重跑 symlink 负例需宿主已有相应权限，不能因此提高权限或降门。

准备的 unit host 包含 7 个原生产 GDScript、固定 data/catalog.json，再加 baseline peer 与测试脚本；这些是 RefCounted 脚本的真实 preload 闭包。runtime.gd 依赖 Catalog，但测试使用 detached public packet/纯 legacy adapter，不构造 Runtime、不推进任何世界。新 project.godot 明确属于格式器单元宿主，自定义 user:// 名称按隔离副本派生；不声称正式项目身份或 1801 世界验收。

后续需要当前获准原生宿主上的已核官方 Godot 4.6.3、Python 3、现有可信 guard。仅经 guard 执行 receipt 中 engine_argv_template；本包不提供绕过 guard 的启动器。引擎串行，实际有效物理预算 8GiB、reserve 至少512MiB，Small 额外1024MiB/120秒及所有更严格既有要求保持。每次 parse/运行均算引擎启动。收集前后源码 hash、runID、owned PID、guard/host/engine exit 和完整 stdout/stderr ERROR/SCRIPT ERROR/WARNING；不得以 exit0 单独宣称干净通过。

单位测试只验证文字输出、schema/形状回退和输入不变。实际 Main/UI 的对象选择、移动提交后的刷新、弹窗、上游公开范围及历史焦点另行验收；届时必须恢复真实876闭包与1801世界，遵守原 Full 门和正式身份绑定，不能用本单元宿主替代。

本入口覆盖 legacy 1/2/10000、typed owner/world、三种 persistent、混合只一条说明、坏包不可用回退、HUD/caption 不变、深输入字节不变。缺少 status_details 的 raw legacy 保持基线回退原文，是现候选的明确范围限制。

本 v2 测试包仅同步已远端逐字节回读的 v2 candidate commit/prefix/六文件 pins。Godot 驱动、check_static.py、prepare.py 及所有 source_inputs/dependency/fixture 字节未改。Git LF 修复仅在 candidate helper；严格原始 hash、guard 和运行范围不变。冻结的 004/005 不修改、不重试，本包没有新 ready ID。
