"""Label the original Blender technical renders without altering model imagery."""
import json
import sys
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parent.parent
rows=json.loads((ROOT/'manifest.json').read_text())['assets']
zh='--zh' in sys.argv
font_path=str(ROOT.parent/'NotoSansCJK-Regular.ttc') if zh else '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
zh_names=['乡村小屋 A','乡村小屋 B','村落谷仓','共用水井','花园宅邸','富户楼房',
          '铁匠铺','手工作坊','窄地民居 A','窄地民居 B','市政会馆','庭院园圃','材料院']
zh_groups={'village':'村落','shared':'共用','rich':'富裕区','industrial':'工坊区','poor':'平民居住区','civic':'市政'}
font=ImageFont.truetype(font_path,17)
small=ImageFont.truetype(font_path,13)
title=ImageFont.truetype(font_path,31)
W,H=1632,2132
sheet=Image.new('RGB',(W,H),'#ECE4CF');draw=ImageDraw.Draw(sheet)
draw.text((28,22),'南潮海岸 · 原创城镇建筑组件' if zh else 'COAST CITY  /  BLENDER DISTRICT KIT',fill='#304A46',font=title)
draw.text((30,65),'13件独立模型 · 地面中心原点 · 单边占地不超过0.55世界单位 · 每件一个材质面' if zh else '13 original modules  |  ground pivots  |  0.55 max footprint  |  one surface each',fill='#54685D',font=font)
for i,a in enumerate(rows):
    x=24+(i%4)*402;y=107+(i//4)*483
    im=Image.open(ROOT/'previews'/(a['id']+'.png')).convert('RGB')
    sheet.paste(im,(x,y))
    draw.text((x+2,y+421),zh_names[i] if zh else a['id'].replace('_',' ').title(),fill='#304A46',font=font)
    line=f"{a['lod0']['triangles']:,} 三角面 · 远景版 {a['lod1']['triangles']:,} · {zh_groups[a['district']]}" if zh else f"{a['lod0']['triangles']:,} tris  |  LOD1 {a['lod1']['triangles']:,}  |  {a['district']}"
    draw.text((x+2,y+445),line,fill='#54685D',font=small)
draw.text((430,1590),'紧凑聚落内，也能看清不同街区的建筑特征' if zh else 'District cues stay within compact settlements',fill='#304A46',font=font)
lines=[
    'Village: clay roofs, timber, shared well',
    'Affluent: pale stone, teal roofs, garden and balcony',
    'Industrial: flues, awnings, tool and storage yards',
    'Modest homes: narrow plots, lean-tos, mixed roof colors',
    '',
    'Full kit: 10,996 triangles; LOD1: 7,148 triangles',
    'No textures, third-party meshes or physics bodies',
    'Building scale is consistent; small props are enlarged here',
    '',
    'Asset inspection renders, not an in-game performance test',
    'Target GTX 1660 Ti / 1080p30 has not been measured',
]
if zh:lines=[
    '村落：陶瓦、木构、共用水井',
    '富裕区：浅色石墙、青瓦、花园与阳台',
    '工坊区：烟道、棚檐、工具和材料院',
    '平民居住区：窄宅、侧棚、不同屋顶颜色',
    '村庄和城邦各一格；最大城市只占几格',
    '',
    '全套10,996三角面；远景版合计7,148三角面',
    '无贴图、无第三方模型、无新增物理碰撞体',
    '建筑保持统一比例；水井、庭院和材料院在此放大展示',
    '这是Blender模型检视图，并非游戏运行截图',
    'GTX 1660 Ti笔记本的1080p30目标尚未实测',
]
for i,t in enumerate(lines):draw.text((430,1628+i*24),t,fill='#54685D',font=font)
draw.text((28,H-41),'原创切面模型 · Blender 4.3.2 · 2026-10-03' if zh else 'Original faceted mesh kit  |  Blender 4.3.2  |  2026-10-03',fill='#54685D',font=font)
out=ROOT/('previews/kit_contactsheet_zh.png' if zh else 'previews/kit_contactsheet.png')
sheet.save(out)
print(out)
