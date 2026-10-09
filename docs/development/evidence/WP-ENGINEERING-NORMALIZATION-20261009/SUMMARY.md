# 本轮工程规范化交付

范围：WP-ENGINEERING-NORMALIZATION-20261009；owner 为 codex-engineering-normalization。源码基线 main `6fc4bf5ad6290b73a71f3ac795f7b64138127624`，独立分支 `candidate/engineering-normalization-20261009`。本记录仅是此次交付凭据，不是项目总计划。共享 STOP 保持，未运行队列、旧013或正式采用。

## 实际改动与核对

- 复用 WORKFLOW 承载阅读顺序、唯一文档职责、目录约定、恢复/测试入口、工具版本、失败分类及精确发布和回退；AGENTS已适用，无需重复修订。根README原空白字节保持。
- `tools/build_evidence_index.py` 从固定Git blob派生58个候选根、225份JSON元数据，关联任务/owner/基线/结果/采用回执/准备入口。快照为本目录 EVIDENCE_INDEX.json；无回执标UNKNOWN，原状态保留，不自动裁决冲突。
- `tools/check_focused_paths.py` 复用旧路径回归，仅把 main 中的场景循环提取为 `check_allowlist_scenarios`。旧候选原件不改；AST还原比对和完整结果字节比较证明这块行为保持。新增缓存忽略规则仅针对 .godot、__pycache__、Python字节码，不忽略验收日志或Godot .uid。
- 核010 `attempt-001/evidence/task_io.py`：临时网络分类在 gate，精确两前缀在 publish；portable-packages-v2的prepare拒绝reparse、绑定原始字节，旧失败和closeout原件保留。旧005宽前缀不再写成010仍未修的问题。
- 核010结果165/234/305，符号链接负例未跑、GUI引擎未启动；核012源码哈希及实际编译/30项managed结果，Win32等价性未测。这些旧成绩未重跑、未扩张。

## 本轮测试与限制

命令均从本分支checkout根执行，完整可复用入口见 WORKFLOW。工具绝对路径保存在本机独立记录，公开结果仅保留版本和Godot哈希。

| 命令/绑定 | 实际结果 |
| --- | --- |
| `python -B -m unittest discover -s tools/tests -v` | 7/7；日志在本目录，包含快照忽略未提交改动、缺失采用、失败结果关联、重复/坏JSON、输出拒绝覆盖、AST还原和完整结果对照 |
| 旧 `regression.py` 与新 `check_focused_paths.py`，相同六目录参数 | 各230项、32场景；完整JSON逐字节一致；path-regression.json保留真实固定源码哈希 |
| `python tools/restore_v30.py --project <正式隔离恢复目录> --check` | exit0；1466源码、347字面脚本、零写入；最终source map见RESULT；没有读二进制资源 |
| `python -B tools/build_evidence_index.py --ref 6fc4bf5ad6290b73a71f3ac795f7b64138127624 --output <新文件>` | exit0；58候选、225元数据、0解析问题 |
| 本目录 `audit_repository.py --repo <checkout> --formal <正式恢复目录> --output <新文件>` | 只读审查；结果在AUDIT.json |

Godot版本探测1次，版本4.6.3；该探测发生在发现仓库AGENTS之前，未使用guard，不能记成受保护运行。之后没有引擎解析/玩法启动。GUI、FPS、IME、完整旅程、原生守卫等价性、录像及旧013均NOT_RUN；未安装新引擎、未降低保护。正式v30和真实玩家档未写入。

初次长路径worktree建立因Windows文件名长度失败，Git已回滚该次创建；改用短隔离路径和命令级core.longpaths后成功。旧队列工作区690条未提交状态保持，不尝试修复。

## 结构债务 按影响排序

| 影响与真实证据 | 建议边界与所需验证 |
| --- | --- |
| 身份与存档兼容：`view/actor_status_profile_v1/source.gd:24 admit`、`:53 profile_digest` 将代码摘要加入identity，再生成world_id；根Main与恢复Main不同 | 不改签名、规则或存档格式。未来先核authority注册表，做同源存档重开、跨版本明确拒绝和恢复链验证 |
| 状态/生命周期耦合：正式 `main.gd:1827 _switch_mode_to` 186行、12模式，同时准备renderer、失效AI上下文、清弹窗、保存UI快照 | 按准备/提交阶段切最小边界；需模式往返、非法切换保持原场景、pending动作、弹窗取消、真实Main/GUI回归 |
| 动态Dictionary与缓存：两个 `view_adapter.gd` 的 `refresh_runtime_state`（65/68行）缓存_phase/_slot；`import_reply`（112/115行）按kind分派多个协议 | 先书面列出输入/输出key及失败返回，不抽通用父类。需坏包、缺key、过期ticket、重复回执、取消后状态测试 |
| 重复逻辑：行动adapter 71函数，状态adapter 74函数；60个同名函数体/整函数相同，整函数合计226行 | 只优先纯辅助函数；已存在不同profile行为不能合并。须两profile对照、错误语义、输入不变及源码身份检查 |
| Main UI可测试性：2900行/175函数/181个顶层变量；`build_ui:452` 203行，`build_dialogs:860` 89行；名字混用build、_switch和多组mode布尔值 | 行数本身不是缺陷。先分离纯显示数据，再做信号连接一次、重建释放、焦点/IME/DPI验证；本轮未重写Main |
| 执行器可移植性：010 `gate`仍把非网络准入失败归为STOP_or_admission_failure，历史task_io带任务常量/机器路径 | 原件不改、不作为通用入口；未来仅在新任务中细分审批/环境/源码故障，再用错误注入测试；不改trusted pin/STOP |

AUDIT口径：以顶层func边界计数，span含结尾空行/注释；同名函数去掉声明后比较，保留单行函数体。原始旧数字不是重构授权。当前60个重复的函数体为190行，连声明的完整函数为226行。

## 文件审查与恢复

1730个已跟踪文件的启发式审查未发现常见缓存/临时扩展名或凭据文件名、所列高风险token模式；这不证明全仓无秘密。208个文本文件含机器路径模式，位置和类型在AUDIT.json，不输出原值；多为历史运行/守卫/测试证据，保留原件，不盲删或迁移。入库的Godot日志属于明确隔离验收证据，不当垃圾清除。文本审查限列出的扩展名且每文件≤2MiB，不解包扫描历史载荷。

新会话先读 `AGENTS.md` → `docs/development/WORKFLOW.md` → 本SUMMARY/RESULT → 索引中所选任务的原manifest/RESULT。按需读共同需求/历史/验收页，不加载全历史。源码运行必须先由v30 manifest恢复独立副本、核check、隔离user://并通过当前guard准入；STOP期间不运行。

回退点为基线main与未改正式v30；本分支无需采用。要撤销工程改动用明确commit的git revert，不reset、不强推、不清空未知目录。候选上传、原页同步与采用分别记录；本轮不合并main。
