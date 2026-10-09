"""Authored settlement overlay, only samples pinned source; never rewrites terrain."""
import json,gzip,math,hashlib,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
b=json.loads((ROOT/'artifacts/world_bundle_20261002/manifest.json').read_text())
read=lambda p:ROOT/p.replace('res://','')
c=json.loads(read(b['runtime']['catalog']['path']).read_text()); nav=json.loads(read(b['runtime']['navigation']['path']).read_text())
t=json.load(gzip.open(read(b['runtime']['source_topology']['path'])))
cs={(x['q'],x['r']):x for x in c['cells']}
center=(-3,17); dirs=[(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0)]
inside=[center,(-3,16),(-2,16)]
gate_inside=(-3,16);gate_outside=(-3,15)
road=[(-1,14),(-2,14),gate_outside,gate_inside,center]
assert all(cs[p]['walkable'] and cs[p]['dry_fraction']==1 for p in inside+road)
key=lambda p:','.join(map(str,p))
assert all(key(d) in nav['allowed_neighbors'][key(a)] for a,d in zip(road,road[1:]))
vs=[v['position'] for v in t['vertices']]
# Local spatial table avoids repeatedly scanning 133k source triangles.
tri=[]
for i,f in enumerate(t['faces']):
 pp=[vs[j] for j in f['vertices']]
 if max(v[0] for v in pp)<-7 or min(v[0] for v in pp)>13 or max(v[2] for v in pp)<15 or min(v[2] for v in pp)>27:continue
 tri.append((i,f,pp))
def sample(x,z):
 for idx,f,p in tri:
  a,d,e=p;den=(d[2]-e[2])*(a[0]-e[0])+(e[0]-d[0])*(a[2]-e[2])
  if abs(den)<1e-12:continue
  u=((d[2]-e[2])*(x-e[0])+(e[0]-d[0])*(z-e[2]))/den
  v=((e[2]-a[2])*(x-e[0])+(a[0]-e[0])*(z-e[2]))/den
  w=1-u-v
  if min(u,v,w)>=-1e-8:
   return {'position':[x,u*a[1]+v*d[1]+w*e[1],z],'source_face_index':idx,'source_face_id':f['id'],'source_barycentric':[u,v,w]}
 raise ValueError(('missing support',x,z))
def xy(h):return [math.sqrt(3)*(h[0]+h[1]*.5),1.5*h[1]]
def corners(h):
 x,z=xy(h);return [(x+math.cos(math.pi/6+math.tau*i/6),z+math.sin(math.pi/6+math.tau*i/6)) for i in range(6)]
def bake_site(slug,name,kind,inner,road,gi=None,go=None,kits=None):
 wall=[]
 for p in inner:
  for d in dirs:
   other=(p[0]+d[0],p[1]+d[1])
   if other in inner:continue
   shared=[v for v in corners(p) if any(math.dist(v,w)<1e-8 for w in corners(other))];assert len(shared)==2
   a,bb=sorted(shared);sa=sample(*a);sb=sample(*bb)
   samples=[sample(a[0]+(bb[0]-a[0])*j/8,a[1]+(bb[1]-a[1])*j/8) for j in range(9)]
   wall.append({'id':slug+':wall_'+key(p)+'__'+key(other),'inside_hex':p,'outside_hex':other,'a':sa['position'],'b':sb['position'],'samples':samples,'is_gate':p==gi and other==go})
 assert all(cs[p]['walkable'] and cs[p]['dry_fraction']==1 for p in inner+road)
 assert all(key(d) in nav['allowed_neighbors'][key(a)] for a,d in zip(road,road[1:]))
 roadpoints=[cs[p]['support']['position'] for p in road];sections=[]
 for a,bb in zip(roadpoints,roadpoints[1:]):
  dx,dz=bb[0]-a[0],bb[2]-a[2];ln=math.hypot(dx,dz);count=math.ceil(ln/.16)
  for j in range(count+1):
   x,z=a[0]+dx*j/count,a[2]+dz*j/count;nx,nz=-dz/ln*.20,dx/ln*.20
   sections.append({'center':sample(x,z),'left':sample(x+nx,z+nz),'right':sample(x-nx,z-nz)})
 sid='settlement:'+b['bundle_id']+':'+slug
 districts=[{'id':'district:'+b['bundle_id']+':'+slug+':'+kit,'name':label,'architectural_kit':kit,'support_hexes':support,'settlement_id':sid} for kit,label,support in (kits or [])]
 return {'schema_version':'coast_settlement_content/v1','id':sid,'name':name,'site_kind':kind,'walled':gi is not None,'scene_id':'scene_coast','bundle_id':b['bundle_id'],'source_mesh_sha256':b['source_identity']['mesh_sha256'],'source_topology_sha256':b['runtime']['source_topology']['sha256'],'catalog_sha256':b['runtime']['catalog']['sha256'],'center_hex':inner[0],'interior_hexes':inner,'gate_id':'gate:'+b['bundle_id']+':'+slug+':main_v1' if gi else '', 'gate_inside_hex':gi or [],'gate_outside_hex':go or [],'road_hexes':road,'road_points':roadpoints,'road_sections':sections,'wall_edges':wall,'wall_height':.42,'wall_thickness':.16,'gate_style':'hinged_twin_leaf','road_width':.40,'districts':districts,'description':name+'：村庄/城邦占一格，大城最多数格；分区以建筑风格区分，不代表已实现居民、生产或经济。','rules':{'ground_wall':'Only the open authored gate edge permits ground passage for walled sites; villages have no perimeter blocker.','flight':'Active flight clears ground-only walls; physical water and air/all blockers still apply.','attack':'Binary wall-edge line-of-sight; closed wall/gate blocks authored attacks regardless of weapon or flight. No projectile arc, wall-height simulation or cover bonus.','gate':'Unlocked manually operated gate; assessed open/close costs one stamina and one action; no key or social lock invented.','economy':'No population, production, ownership or economy simulation.'}}
result=bake_site('south_watch_v1','南坡城','large_city',inside,road,gate_inside,gate_outside,[('affluent','富人区',[center]),('industrial','工业区',[(-3,16)]),('modest','贫民区',[(-2,16)])])
result['additional_settlements']=[
 bake_site('ridge_village_v1','坡田村','village',[(-4,15)],[(-1,14),(-2,14),(-3,15),(-4,15)],kits=[('rural','村落屋舍',[(-4,15)])]),
 bake_site('west_citadel_v1','西坡城邦','city_state',[(-6,17)],[(-1,14),(-2,14),(-3,15),(-4,15),(-5,15),(-6,16),(-6,17)],(-6,17),(-6,16),[('civic','城邦中心',[(-6,17)])])]
scan=json.load(open(ROOT/'artifacts/settlement_20261003/placement_scan.json'))
for place in [result]+result['additional_settlements']:
 assert all(not scan['mountain_intersection'][key(h)] for h in place['interior_hexes']+place['road_hexes']), 'Mountain overlap rejected'
 place['excluded_mountain_manifest_sha256']=b['runtime']['mountain_manifest']['sha256']
result['scale_policy']={'village_hexes':1,'city_state_hexes':1,'large_city_hexes_max':3,'districts_may_share_hex':True,'source':'project-scale-policy'}
p=ROOT/'artifacts/settlement_20261003/content_v1.json';p.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n');print(p);print(hashlib.sha256(p.read_bytes()).hexdigest());print([(x['name'],len(x['interior_hexes']),len(x['wall_edges']),len(x['road_sections'])) for x in [result]+result['additional_settlements']])
