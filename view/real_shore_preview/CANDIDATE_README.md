# 真实海岸局部几何与渲染诊断 v0.2

运行：在已有game项目根目录执行 `sh tests/real_shore_preview/run.sh c`。

- N：原冻结真实PL与新局部PL候选真正A/B
- M：中性材质/岸材质v2；新候选使用自己的actual PL/wet polygon岸距缓存
- G：原完整六角格线；T：固定顶俯；C：有限正交斜俯近景；F12：实际GL截图
- 真实1×，两状态保持同相机、灯光、材质参数、原XZ与face/vertex身份

新几何是artifacts/natural_coast_rebuilt_20261002/candidate_display.json的只读诊断副本。149原顶点的Y变更、局部水footprint重裁都明确标记；冻结source/旧receipt没有修改。此候选不继承acceptedworld，未重跑新drainage/climate/zones科学链，也没有游戏状态。

## 已验证的有用变化

同中性材质的01/02顶俯对比证明原六角阶梯确实变为跨格弧，并非水shader漂移。几何worker独立局部核算14个affected完整原H最低支持81.6804%，大折角p95由81.43°降至38.95°，>60°拐点7降至1。它仍有72.33°残角，不能宣称完全自然或整世界已接受。科学producer/independent证据在该候选自己的目录中。

同材质v2的04/05有限近景显示真正轮廓差异；所有显示顶点仍引用同原face有序坐标。新的display normal是由同源PL相邻面面积加权后归一，原地形与拾取PL不动；纹理底色统一中性，去掉原hex.domain导致的小棕三角块。slope材质权重采用该display normal插值，避免逐face硬切的受光格痕。

岸材质v2将沙宽收紧为world 0.11–0.40，并按实际近岸PL坡度收缩，沙的visual availability用共享world field缓变；湿土带独立、低对比，避免均匀黄黑描边。浅水转深水颜色用同source face的真实depth，海depth scale9，湖22；不假造底高，不增加波浪特效。所有visual参数都不参与80%面积证书。

原生观察没看见水岸露底gap、外扩水面、宽白沫或黑岸；原细拓扑的残角仍可见。新美术质量仍是研究试验，未标最终PASS。

## 资源与范围

海局部4512原faces；候选含保留湖的2889水triangles；terrain1批+ocean1批+原未改lake1批+grid，4材质；候选GPU mesh attributes约1,065,744字节、岸atlas2,359,296字节。新atlas离线7.28s；原生display build约0.95s。本机Godot4.6.3 Compatibility Mesa llvmpipe。此前v0.1有限近景实测22.47fps/p95 50.16ms；这不是v0.2、整图或1660Ti保证。没有compute/Decal/SSR或每帧全域CPU检测。

具体SHA、camera、code、device与actual captures全部保存在每张PNG旁的JSON。缓存与报告不是authority receipts。源输入的Library依赖沿用README.md准确列表，本包不重复大mesh/drainage/旧zip/纹理资产。

本源码包同时含独立frozen-shore材质入口和candidate诊断入口。前者不修改真实岸线；后者只展示明确标识的新局部候选。两者都不写旧loader、main、core或game state。

reader额外保持16个未改lake:3940源footprints与14条未改湖岸段。目标海替换不删除其他水体；最终候选visual field283岸段、2857全部显示footprints。

当前v2实际材质参数与shader SHA见V2_RENDER_PARAMETERS.json；原field manifest中的render_visual_parameters是v0.1历史default，不是v2运行参数或科学area authority。
