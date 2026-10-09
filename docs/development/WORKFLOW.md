# Words and Perils 开发操作规范

适用：公开发行恢复链 v30、独立候选与 Git 证据协作。规则来源为所有者指令、仓库 AGENTS、锁定协议及各版本 manifest/receipt；本文不授予权限，也不是第二份总计划。当前任务、owner、阻塞与下一步只维护在所有者指定的唯一共同总计划；公开仓库不得写入私有计划 URL、私人任务 metadata、密钥或真实玩家档。

## 阅读顺序与文档职责

1. `AGENTS.md`：协作边界；再读本文件的对应小节，不默认加载全历史。
2. 本文件：目录、恢复/运行/测试命令与操作规则。
3. 本任务的 TASK/CLAIM、manifest/INPUTS、RESULT：精确输入、唯一写者与证据范围。旧 ready 不是新授权，终态不重投。
4. `updates/v30/adoption_receipt.json`：公开 v30 有限采用依据；`updates/v30/manifest.json`：恢复链与原始字节。只在涉及发行时读。
5. `tools/build_evidence_index.py` 派生的 JSON：查找候选、任务、owner、基线、结果与采用凭据，不人工抄维护状态。每个字段带原件路径；空列表及 UNKNOWN 必须核实。

共同文档各司其职：总计划仅当前目标/任务/负责人/阻塞/下一步/证据链接；需求页仅产品要求和后期启动条件；规范页仅共同规则；历史页仅决策原因与旧失败；验收页仅版本和原始报告入口。历史中的“当前/下一步”仅为当时快照，不授权运行。仓库根 README 保持空白。

## 目录与新增文件约定

| 位置 | 唯一用途 |
| --- | --- |
| 根 `project.godot/main.gd`、`source_bundle*`、`updates/` | 发行载荷和版本恢复控制；根 Main 不等于恢复后的 v30 Main |
| 恢复目录 `core/`、`view/`、`data/` | manifest 对应的实际规则、界面与数据源码 |
| `assets/`、`resource_packs/` | 资源及分卷；许可证保留在原位 |
| `tools/` | 可复用离线工具；旧恢复器按原哈希保持 |
| `tools/tests/` | 工程工具的离线回归，不能宣称游戏通过 |
| `candidates/<family>/<revision>/` | 一个固定基线的候选；production/overlay、test-only 与 patch 分列；旧目录不重写 |
| `coordination/local-work/results/<task-id>/` | 既有队列结果，不启动/改写旧任务 |
| `docs/development/evidence/<task-id>/` | 非队列工程整理的去敏记录及派生快照；不是 inbox/ready |

新增任务先记录 task ID、唯一 owner、base commit、明确路径清单、测试目标、环境和回退点。准备器/manifest 定义文件级输入，候选发布路径不能使用整个 candidates 或 results 根。旧失败、旧候选和未知采用状态保留，不为整齐搬家。缓存、临时输出、真实存档留在任务隔离目录；已入库疑似生成物先确认归属与可恢复性再处理。

## 最短离线入口

要求 Python 3.10+、Git；本轮验证过 Python 3.12.8 / Git 2.44.0.windows.1 / PowerShell 7.6.5。cwd 始终为本候选 checkout 根。先用 `Get-Command python,git,pwsh` 核实本机绝对路径，写入本机工具记录，公开记录去除用户目录。Windows checkout 使用 Git `-c core.longpaths=true -c core.autocrlf=false` 可避免长路径及自动换行破坏固定输入；不全仓 renormalize。

```powershell
# 只生成索引；输出父目录先建立在本任务隔离目录，文件必须不存在
python -B tools/build_evidence_index.py --ref <固定commit> --output <新index.json>
# 工程工具回归；不运行 Godot，不接触队列和玩家数据
python -B -m unittest discover -s tools/tests -v
```

索引只读该 commit 的 Git blob，忽略未提交内容；返回 0 表示完成且 JSON 元数据无解析问题，1 表示索引已保存但存在 issues，2 表示 CLI 用法/已有输出错误。错误输出保留。index 的 REVIEW_RECEIPT_SCOPE 只表示找到了相关采用回执，必须阅读其有限范围；没有回执只能记 UNKNOWN。候选间共享任务的关联不表示它们被组合采用。

路径回归可单独运行（输出文件必须新建）：

```powershell
python -B tools/check_focused_paths.py --clock-v2 candidates/status-clock-display/20261009-cloud-v2 --clock-v3 candidates/status-clock-display/20261009-cloud-v3 --clock-tests candidates/status-clock-display-tests/20261009-cloud-v3 --focus-v2 candidates/focus-location-display/20261009-cloud-v2 --focus-v3 candidates/focus-location-display/20261009-cloud-v3 --focus-tests candidates/focus-location-display-tests/20261009-cloud-v3 --output <新path-result.json>
```

它是旧 `focused-display-path-regression/20261009-cloud-v3/regression.py` 的行为保持整理，仅提取场景循环。检查真实固定表达式的 Windows/POSIX 路径语义；不是 Win32 文件系统、符号链接权限或引擎验收。退出 0 且结果所有断言通过才算该范围通过，异常非零。

## 恢复与运行入口

正式 public v30 为 `e8ec5db0341f8b4a8aaa0a933e5968c33440c9da`，按 `updates/v30` manifest/adoption receipt 选择；private/Library v28 是另一发行身份，不混文件或存档。不要直接启动仓库根 Main。

```powershell
# 新的独立 checkout，禁止覆盖原安装或已有工作树
 git -c core.longpaths=true -c core.autocrlf=false worktree add --detach <新的隔离项目目录> e8ec5db0341f8b4a8aaa0a933e5968c33440c9da
# 在该新目录作为 cwd，先恢复；已有正式恢复副本只需对应 check
 python tools/restore_v30.py --project <隔离项目目录> --sources-only
 python tools/restore_v30.py --project <隔离项目目录> --check
# 完整资源恢复仅在需要实际运行且任务准入齐全时做
 python tools/restore_v30.py --project <隔离项目目录>
```

`--check` 只读源码/映射/字面闭包，不读二进制资源；`--sources-only` 写源码；无模式选项会恢复源码与资源。错误非零、失败产物保留；恢复成功不等于引擎成功。旧恢复器保留分层回滚与未知修改拒绝，不宣称整次恢复或断电原子性。原始输入按 bytes/SHA 校验，不能为匹配 hash 改旧换行。

本机已存在 Godot 4.6.3，历史路径 `E:\WordsAndPerils-Test\Godot\4.6.3\Godot_v4.6.3-stable_win64.exe`；先核文件与已记录版本/哈希，不重复安装。实际启动，包括版本/帮助/解析，必须服从适用 guard。完整运行入口是**已核正式恢复副本 + 任务隔离 user:// + 当前准入通过的既有原生 guard**；本文不提供裸启动命令。GUI guard 尚无原生等价性验收，STOP 生效期间运行记 NOT_RUN，不能用另一路径绕过。

聚焦格式器使用010的 `candidates/player-details-local-verification/20261009-local-010/portable-packages-v2/{clock,location,combined}/prepare.py` 及对应 INPUTS/TEST_MANIFEST。按各包用法把 source-root/candidate-root/work-root/name 传全，先核 pins；输出 `PREPARATION_RECEIPT.json` 的参数模板仍须经准入与 guard，不直接执行。010已存在165/234/305结果、失败原件和符号链接负例未跑项；012已存在C#编译/30项managed结果；查原结果，不重投终态、不借此宣称GUI或Win32保护通过。

## 执行与失败分类

小任务认领 → 小改 → 对应测试 → 核对诊断、退出及源码 → 保存。源码静态检查与引擎分开；有用户授权的独立源码/文档工作可继续，不因无关环境阻断全部停止。命令记录 cwd、绝对工具路径/版本、参数、输入 hash、退出码、stdout/stderr、输出、限制和未跑项；进程 exit0 不保证断言和诊断干净。

| 类别 | 结果与动作 |
| --- | --- |
| 用户 STOP/取消 | 停止对应运行；只有新的明确授权才能改变范围，不自动解除共享 STOP |
| 审批拒绝 | 记录原动作和理由；不换执行器、会话或安全设置绕过。仅缺原授权证据时补证后原工具重试一次 |
| 环境缺失 | blocked，列缺失条件；不安装替代品或降低阈值冒充通过 |
| 临时网络失败 | 保存原始字节，受影响动作暂停；最多有界只读恢复，同因两败停止原样路线；恢复后重核来源/pin/STOP/claim/锁/去重 |
| 代码/断言失败 | failed；修复后只跑受影响项，保留失败原件 |
| 未启动/未执行 | NOT_RUN，注明原因；不得算通过或当作代码失败 |
| 状态 UNKNOWN | 先读回核实，不能当安全重开或完成 |

010 `evidence/task_io.py` 已有 transient_network 分类、精确本任务两个发布前缀、失败记录保留；portable packages 已处理路径及换行。它是010历史执行证据，含终态任务/本机路径，不是通用 worker，禁止直接运行。旧005宽路径和旧网络锁存说明仅是历史，不作为仍未修复的同一入口。更细 admission 分类和通用化仅列后续债务，不改可信协议/pin。

## 引擎保护与验收范围

共享 STOP/CONTROL、唯一写者、固定版本、原守卫及真实物理指标始终有效。真实容量上限 `min(真实物理容量, 8 GiB)`，物理预留至少512 MiB；Small额外1024 MiB/120秒，Full额外1741 MiB/180秒，保留更严格要求；Job commit 不是 RSS。指标不可读、准入不足、来源/claim不明或STOP生效不启动。引擎、大复制/hash和渲染串行，不杀未知进程；记录guard/host/engine退出、reader完成、Job清空及owned句柄身份。真实存档与正式安装不触碰。

`--check-only --script` 仅解析；headless不代替Main GUI、鼠标、IME、DPI、视觉、FPS、长跑或完整旅程。涉及存档格式、规则、签名、分发身份和profile_digest的改动另立边界及兼容性验收，不借去重修改。受影响行为先有基线再小步整理，不全仓格式化、不一次重写Main。

## 保存、远端核对与回退

PowerShell多命令必须逐步检查 `$LASTEXITCODE`，或以 `subprocess.run(..., check=True)` 串行控制；不能依赖分号在失败后自动停止。原始Windows输出保留CRLF，差异检查使用 `core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol` 识别其行尾，不为清诊断重写证据。

只 stage 明确列出的本任务文件，先审 `git diff --cached --name-status`，不执行宽目录全量提交。独立候选分支只普通push，不force、不自动合main、不改变可见性、不启用Actions。需要main发布时由协调者按当前head、单亲提交、expected-head CAS/快进规则处理；main变化先重核任务输入，不能覆盖别人工作。

发布后核远端分支commit，并按该commit逐字节回读每个本任务文件，结果记文件数/字节/hash。先提交产物，再另存发布回读凭据，避免自引用hash。空状态不产生空提交。

回退：此轮仅候选分支，直接继续使用未改的正式v30；需要撤销已提交工程改动时在候选分支做明确commit的 `git revert`，不reset --hard、不改历史。隔离目录及失败记录先保留；不能从未知dirty工作区覆盖回原项目。

## 一手技术依据

- [Git gitattributes](https://git-scm.com/docs/gitattributes.html)：index/工作树换行有区别，固定hash绑定原始字节。
- [Godot 4.6命令行](https://docs.godotengine.org/en/4.6/tutorials/editor/command_line_tutorial.html)：解析与运行的证据范围分别记录。
