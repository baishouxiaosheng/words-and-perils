# 真实 r24 海岸／水／生态地面／局部植被集成诊断

此独立 namespace 结束“只能看人工七格”的限制。默认完整真实新 r24 世界顶俯、真实高度 1×，可以切换真实局部。它不改旧 readonly loader/view、main、游戏状态或冻结科学 source/data/receipts。

## 状态与运行

源候选 `natural_coast_ecology_v02_WHOLE_PENDING.json` SHA `e6219347d90c5d4c8de5d61aaa9436542fd254810d17eff7afeb3d3ae22b8318`。集成视图始终明确 `DIAGNOSTIC_PENDING`；独立科学审核、relief envelope、实际 canopy density 和最终美术验收不由这个 renderer 发证。不能借旧生态或旧 mesh/climate receipt。

运行：`sh tests/integrated_ecology_world/run.sh`

- 1 全图完全顶俯；2 实际海岸；3 实际生态过渡；4 真实湖局部
- V 同镜头植被 on/off；G 原完整 hex 格线；J B1 林下共享草土；K B2 独立可见材质混合；B 岸装饰 on/off
- 右键有限角度、滚轮有限近景、中键平移；左键只读原 face/bary/完整 hex 拾取
- F12 实际原生截图；F9 全图及局部同镜头植被证据；F10 当前相机性能样本

## 真来源与显示边界

- 每顶点实际 original face_index、有序 source barycentric；XYZ 为同源 designed_height 插值，无伪高度、全格抬平、显示水域扩张或拾取坐标改写
- 新海岸 mesh/drainage/climate，202 实际水体。水仅真实 footprint + source level；没有真实 river footprint，完全不画假河或宣称河岸完成
- source shells 与实际 dry 硬裁。dry 内残留 ocean/main_lake 权重不铺蓝水颜色，显式记录为未知陆侧岸土诊断；不作为森林密度、科学白名单或正式验收
- B1 forest/jungle 共草土地面，森林由实际局部树簇表达。B2 离线同一 world-XZ 归一四种视觉土层，10–90 混合约 0.24 world；不修改源生态、K、geometry、80%支持面积。没有坐标 warp，wet/exterior coordinate warp 为零
- 冠幅是实际 heptagon 模型投影；根点 source face/bary、合法 dry/eligible 与实际 PL slope≤.6；实际 crown union、原 square 和原完整 H 分母另计。eligible 域绝不算作 actual cover

## 成本与未通过项

一次 CPU 离线 chunk cache，少数共享材质及 MultiMesh，不依赖 compute、Decal、SSR；runtime 只读／解压一次，不逐帧 parse 巨大科学 JSON 或 clip 全图。所有地表、水、树、格线共 identity-transform；相机动作才更新树预算和 LOD。

当前只放合法局部固定 seed 植被，最多 12,000 可见实例，全图最多显示缓存实例的 12.5%。预算／LOD／未布置区域都意味着欠 cover，不能用性能预算换密度 PASS。缓存实际 density、V/H 和 source-domain 留在 `render_binding_audit.json`；所需完整 density/K 门槛仍未通过。

Godot 4.6.3 Compatibility / cloud llvmpipe 原生数字不代表 1660Ti 笔记本 1080p≥30fps 通过。世界约 88×77、高度约 -0.37…2.10，全图很平缓；近景保持 1× 不私自放大。最终以真实截图／性能报告记录可读性、黑岸、三角格痕、硬分界、浮树与模糊问题。

## 上游依赖

请在已有 game 项目叠加此 source/cache 包。源科学数据由 manifest 按实际 SHA 引用；不重复打包巨大 mesh/drainage/climate/zone JSON，不嵌旧 ZIP。保留原 `view/ecology_preview/vegetation_meshes.gd` / `vegetation_surface.gdshader` 的 namespace、recipe 和许可，仅纯显示复用。纹理使用已有 Poly Haven CC0 soil/rock；字体使用已有 NotoSansCJK-Regular.ttc，白色加粗、无描边、宽外阴影。

## Default gameplay art profile (2026-10-02)

The compact66 real-world presentation now applies the original clear-daylight/TABS-inspired gameplay profile when natural_v2 canopies load. See [the visual recipe and official references](tabs_style/README.md). This is a reversible material/lighting change: real source geometry, source height, shore support, river replacement and picking are unchanged. All current chess pieces are styled by stable chess-piece metadata, including nodes renamed by Godot. Native comparison evidence is in `artifacts/tabs_style_20261002/`; cloud software-renderer timings do not establish GTX1660Ti performance.
