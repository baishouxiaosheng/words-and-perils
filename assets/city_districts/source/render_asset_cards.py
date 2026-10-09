"""Small independent Blender renders; never runs Godot or edits exported assets.

blender -b -t 2 --python assets/city_districts/source/render_asset_cards.py
Then: python assets/city_districts/source/assemble_contactsheet.py
"""
import bpy
import json
import sys
from mathutils import Vector
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'source/city_district_kit.blend'))
scene=bpy.context.scene
manifest=json.loads((ROOT/'manifest.json').read_text())
names={a['id'] for a in manifest['assets']}
objects={n:bpy.data.objects[n] for n in names}
for obj in objects.values():
    obj.location=(0,0,0)
    obj.hide_render=True
scene.render.engine='CYCLES'
scene.cycles.samples=32
scene.cycles.use_denoising=False
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=384;scene.render.resolution_y=416
scene.render.resolution_percentage=100
camera=scene.camera
for lamp in [o for o in scene.objects if o.type=='LIGHT']:
    lamp.location=(-3,4,8)
    lamp.rotation_euler=(Vector((0,0,.5))-lamp.location).to_track_quat('-Z','Y').to_euler()
    lamp.data.energy=850
for asset in manifest['assets']:
    if '--only' in sys.argv and asset['id'] != sys.argv[sys.argv.index('--only')+1]:continue
    obj=objects[asset['id']];obj.hide_render=False
    # Keep a common camera for buildings, enlarge small props for inspection.
    is_prop=asset['height']<.7
    center=Vector((0,0,asset['height']*.43))
    camera.location=center+Vector((2.6,4.5,3.2))
    camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=1.66 if not is_prop else .87
    scene.render.filepath=str(ROOT/'previews'/(asset['id']+'.png'))
    bpy.ops.render.render(write_still=True)
    obj.hide_render=True
print('CITY_CARDS_RENDERED',len(names))
