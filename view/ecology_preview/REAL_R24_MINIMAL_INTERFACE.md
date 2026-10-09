# 下一阶段：真实 r24 局部只读预览的最小接口

状态：接口提案，尚未实现通用 whole consumer。当前 `cache_loader.gd` 只接三份已审核字节快照；删除 fixture 检查或增加 SHA 白名单不能替代真实上游语义验证。下一阶段优先选择真实海岸／河岸局部场景，不再扩展人工 7hex 美术样本。

## 1. 最小输入与准入

复用冻结 terrain/water loader 的输出，新增一个独立版本的局部生态 adapter，不写旧 loader、世界事实或 Game state。所有路径都属于本地只读来源；源文件在 manifest 中记录实际 byte SHA256，语义摘要与 schema 分开保存。

| 输入 | 实际需要的只读字段 | 准入条件 |
|---|---|---|
| 原 mesh | schema／geometry version、seed／radius、semantic hash；稳定 vertex ID、XZ、designed_height；稳定 face ID、face.vertices 的有序三索引；原 hex ID 与完整 polygon | 与已冻结 r24 身份一致；不得按局部裁切重编号后失去原 face 身份 |
| drainage／water | schema、mesh byte／semantic binding；源 face ID／index；真实 wet polygons、源 level、water type；现有 source shoreline／depth 信息（若有） | 同源 mesh；水足迹／level 由来源决定。没有真实 river footprint 时 river 模式保持不可用 |
| final climate＋dry support | 正式 final receipt 的实际文件 SHA；mesh/water binding；dry face＋bary polygons 与状态 | climate final 只证明 climate，不替代 zone whole acceptance |
| accepted zones | zone schema／config SHA／palette linear RGB；zone masks 的 face_index、face_id、original_hex_id、domain、ecology、cover_eligible、local_detail_weights、vertices.barycentric；真实 shell vertices.weights；protected_core_masks K；cover proposal 与 density domain 定义 | 独立审核的完整来源 receipt 必须绑定全部输入与 mask 文件；candidate、PENDING、SMALL_FIXTURE 不可升级为 accepted |
| scope | 少量真实原 hex／face ID、XZ bounds、边邻 halo、固定相机 | 只选取来源，不产生新 biome、shore 或 relief |

source classification／river reserve 若存在于 zone identity.files，也必须一并按实际 SHA 绑定。未知 ecology label 或 shell 中的 ocean/main_lake label必须显式报告，并以真实 dry domain 硬裁；不可当作 forest density。

## 2. 只生成四种小缓存

### A. 局部 PL render cache

输入是 accepted mask，输出保留原 face ID／index、有序 barycentric、同源生态权重／local detail，以及 source identity。每个渲染顶点由原 face 的 designed_height 插值。局部裁切只能裁显示范围，不能抬平、逐 hex 建山或改 source support。独立核对面积闭合、shell junction、face/bary 与实际 GPU 顶点。

### B. 真实岸材质 cache

只在来源实际 water／dry footprint 上，离线计算 shore distance、source level 与 PL ground 的 depth（仅可用来源能确定的项）。浅水色与沙滩宽度是明确视觉参数；水面仍逐来源 footprint 和 level。缺真实 shore/depth 字段时只允许从这些不可变真实 polygons／PL 派生，记录 exporter SHA 与算法版本。不得用全平面、shader 假位移、模糊 wet mask 或材质外扩改变水域。

### C. 实际 cover cache＋测量 ledger

只在 source cover_eligible dry domain 与合同允许 PL slope 上采样。输出固定 seed、原 face/bary anchor、model recipe/license/hash、实际 yaw/scale、投影冠幅 polygon 和批次信息。按合同固定 world square `.25D`，用全部实际冠幅 union 重算每格实际密度；保存源支持面积、原 hex H、V、K∩V、失败碎域面积／H。密度分母采用合同定义并保留完整原 square 对照。树量上限或 LOD 删除必须报告欠覆盖，不得作为密度 PASS。

### D. 独立 visual ground cache（可选）

真实 source shells／支持分类始终保留。forest/jungle 可共享底土，低成本 AO 由实际 cover 而非整格黑涂层派生；距离混合、material zero-line warp 属于独立视觉命名空间，不写 source masks／K／80% receipt。记录固定 seed、XZ 宽度／振幅、完整 dry inside mask、相邻 chunk 共用 world-coordinate field、三岔归一与视觉交换诊断。真实 wet／exterior coordinate warp 必须严格为零后才能声明该项通过。现有无水 7hex B3 没有这份证明。

## 3. 最小 consumer 与验证

1. 先校验完整上游 receipt／schema／SHA／face 顺序／domain，再构建新的局部 display root；失败时保持旧 view 不变。这里需要独立 semantic adapter，不借当前 fixture 白名单过关
2. 地形、水、格线、vegetation 共父变换；默认真实 1×。2×只作明确展示，inverse picker 仍回到同一真实 source 坐标
3. 静态 CPU 离线缓存、少数材质和 MultiMesh 批次。Compatibility 不依赖 compute、Decal、SSR；不做全帧 CPU 域检测。每 chunk 统一 halo 与 atlas 世界坐标，报告显式字节／几何／实例预算
4. 先拍真实局部的同相机旧／新、近中远、grid on/off、trees on/off，查岸 gap／depth／draworder；截图保存实际 source、cache、shader、camera hash。极小 fixture 软件 FPS 不迁移为 r24 或 1660Ti 的保证

## 4. 当前可走与阻塞

已有入口 `sh tests/ecology_preview/run.sh w` 可以消费冻结真实 r24 mesh/drainage，作为中性材质／灯光／水研究。代码存在但尚未原生 QA；无 zone 时不加 biome／cover，不能展示为真实生态完成。

当前缺 independently accepted whole zone mask/receipt，故 A/C/D 的真实生态接入保持阻塞。可以先做真实海湖局部的 B 与受光材质检验。真实 river footprint 若未完成，也继续阻塞 river 岸线，不由 fixture 或 centerline 补造。此接口文档没有解除以上 gate，也不代表新 consumer 已写完。

机器可读字段清单：`REAL_R24_INTERFACE_PROPOSAL.json`。该清单只有 required field names，没有伪造输入 SHA 或 accepted receipt。
