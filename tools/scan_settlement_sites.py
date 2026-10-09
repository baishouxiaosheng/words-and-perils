import json,gzip,struct,math,pathlib,collections
root=pathlib.Path(__file__).resolve().parents[1];b=json.load(open(root/'artifacts/world_bundle_20261002/manifest.json'));p=lambda v:root/v.replace('res://','');cat=json.load(open(p(b['runtime']['catalog']['path'])));nav=json.load(open(p(b['runtime']['navigation']['path'])));mp=p(b['runtime']['mountain_manifest']['path']);m=json.load(open(mp));arr=struct.unpack('<%df'%(m['vertices']*8),gzip.open(mp.parent/m['binary'],'rb').read());tris=[]
for i in range(0,len(arr),24):
 t=[(arr[i],arr[i+2]),(arr[i+8],arr[i+10]),(arr[i+16],arr[i+18])];tris.append((t,min(x for x,y in t),min(y for x,y in t),max(x for x,y in t),max(y for x,y in t)))
def cross(a,d):return a[0]*d[1]-a[1]*d[0]
def sub(a,d):return(a[0]-d[0],a[1]-d[1])
def clipped_area(poly,clip):
 for a,b in zip(clip,clip[1:]+clip[:1]):
  edge=sub(b,a);inp=poly;poly=[]
  if not inp:return 0
  for p,q in zip(inp,inp[1:]+inp[:1]):
   dp=cross(edge,sub(p,a));dq=cross(edge,sub(q,a));pin=dp>=-1e-9;qin=dq>=-1e-9
   if pin:poly.append(p)
   if pin!=qin:
    t=dp/(dp-dq);poly.append((p[0]+t*(q[0]-p[0]),p[1]+t*(q[1]-p[1])))
 return abs(sum(cross(p,q) for p,q in zip(poly,poly[1:]+poly[:1])))*.5 if poly else 0
cs={(x['q'],x['r']):x for x in cat['cells']};clean={};intersects={}
for h,row in cs.items():
 if not(-14<=h[0]<=2 and 10<=h[1]<=23):continue
 x,z=math.sqrt(3)*(h[0]+h[1]*.5),1.5*h[1];poly=[(x+math.cos(math.pi/6+math.tau*i/6),z+math.sin(math.pi/6+math.tau*i/6)) for i in range(6)]
 hit=any(clipped_area(t,poly)>1e-7 for t,x0,z0,x1,z1 in tris if x0<=x+.867 and x1>=x-.867 and z0<=z+1 and z1>=z-1)
 intersects[h]=hit
 if row['walkable'] and row['dry_fraction']==1 and not hit:clean[h]=row
print('CLEAN',sorted(clean));start=(-1,14);prev={start:None};queue=collections.deque([start])
while queue:
 h=queue.popleft()
 for key in nav['allowed_neighbors'].get('%d,%d'%h,[]):
  nxt=tuple(map(int,key.split(',')))
  if nxt not in clean or nxt in prev:continue
  prev[nxt]=h;queue.append(nxt)
for h in sorted(clean):
 route=[];cur=h
 if h not in prev:continue
 while cur is not None:route.append(cur);cur=prev[cur]
 if len(route)<=12:print('REACHABLE',h,cs[h]['ecology'],route[::-1])
json.dump({'clean':[list(h) for h in clean],'reachable':[list(h) for h in prev],'mountain_intersection':{'%d,%d'%h:v for h,v in intersects.items()}},open(root/'artifacts/settlement_20261003/placement_scan.json','w'),indent=2)
