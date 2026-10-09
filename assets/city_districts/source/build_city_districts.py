"""Original faceted miniature architecture, built and exported by Blender 4.3+.

blender -b -t 1 --python source/build_city_districts.py
blender -b -t 2 --python source/build_city_districts.py -- --render

No downloaded geometry, textures, add-ons or Python dependencies. Dimensions
are deliberately miniature/exaggerated to read over the map's 1.15-unit walls.
The .blend is kept in a .gdignore directory: Godot consumes explicit .glb files.
"""
import bpy
import math
import json
import hashlib
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
P = {
    'ivory': 'F4DCAA', 'plaster': 'E5AD72', 'cream': 'F0C68D',
    'salmon': 'D77963', 'sage': 'A9BE96', 'blue': '8AB9C6',
    'timber': '674E3D', 'wood': 'AA784E', 'woodlight': 'C69460',
    'clay': 'CC6145', 'claylight': 'E78B5D', 'teal': '417F89',
    'teallight': '66A3AC', 'slate': '617984', 'slatelight': '849DA5',
    'stone': '9AABAA', 'stonelight': 'CBD1BB', 'stonedark': '758684',
    'glass': '305361', 'glasslight': '79AFB9', 'dark': '394744',
    'brass': 'D7AE50', 'green': '63955F', 'leaf': '9EB36A',
    'flower': 'DD795F', 'soil': '8B6D49', 'canvas': 'EECF85',
    'water': '4D8B9A', 'brick': 'B9785A', 'iron': '526269',
}

def rgb(key):
    h = P.get(key, key)
    # Hex palette is display-sRGB; mesh corner color storage is scene-linear.
    def lin(v):
        v = int(v, 16) / 255
        return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4
    return tuple(lin(h[i:i+2]) for i in (0, 2, 4))

class Builder:
    def __init__(self, name, detail=True):
        self.name, self.detail = name, detail
        self.v, self.f, self.c = [], [], []
    def part(self, verts, faces, color, shades=True):
        # Every component including the thin solid pennant is a closed
        # solid. Normalize winding without modifiers or double-sided materials.
        volume=0.0
        for face in faces:
            a=Vector(verts[face[0]])
            for k in range(1,len(face)-1):
                volume+=a.dot(Vector(verts[face[k]]).cross(Vector(verts[face[k+1]])))/6
        if volume < -1e-9: faces=[tuple(reversed(f)) for f in faces]
        offset = len(self.v)
        self.v.extend(verts)
        base = rgb(color)
        for i, face in enumerate(faces):
            self.f.append(tuple(offset + j for j in face))
            # Restrained hand-authored face-value pair, not a baked light/shadow.
            factor = (1.0 if i % 3 else .88) if shades else 1.0
            self.c.append(tuple(c * factor for c in base) + (1.0,))
    def box(self, p, d, color, yaw=0, bevel=0):
        x,y,z=p; w,h,t=[a/2 for a in d]
        if bevel:
            b=min(bevel, w*.35, h*.35)
            ring=[(-w+b,-h),(w-b,-h),(w,-h+b),(w,h-b),(w-b,h),(-w+b,h),(-w,h-b),(-w,-h+b)]
        else:
            ring=[(-w,-h),(w,-h),(w,h),(-w,h)]
        n=len(ring); co,si=math.cos(yaw),math.sin(yaw)
        verts=[(x+a*co-b*si,y+a*si+b*co,z+c) for c in (-t,t) for a,b in ring]
        faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
        faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        self.part(verts,faces,color)
    def beam(self,a,b,width,color,depth=None):
        a,b=Vector(a),Vector(b); direction=b-a
        q=direction.to_track_quat('Z','Y')
        w=width/2; d=(depth or width)/2; h=direction.length/2
        verts=[tuple(q@Vector(v)+(a+b)/2) for v in [(-w,-d,-h),(w,-d,-h),(w,d,-h),(-w,d,-h),(-w,-d,h),(w,-d,h),(w,d,h),(-w,d,h)]]
        self.part(verts,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],color)
    def cylinder(self,p,r,h,color,n=10,top=None):
        rt=r if top is None else top
        verts=[(p[0]+rr*math.cos(i*2*math.pi/n),p[1]+rr*math.sin(i*2*math.pi/n),p[2]+z) for z,rr in [(-h/2,r),(h/2,rt)] for i in range(n)]
        self.part(verts,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],color)
    def roof(self,p,w,d,rise,color='clay',trim='claylight',hip=False):
        x,y,z=p
        if hip:
            v=[(x-w/2,y-d/2,z),(x+w/2,y-d/2,z),(x+w/2,y+d/2,z),(x-w/2,y+d/2,z),
               (x,y-d*.23,z+rise),(x,y+d*.23,z+rise)]
            self.part(v,[(3,2,1,0),(0,1,4),(1,2,5,4),(2,3,5),(3,0,4,5)],color)
            self.beam(v[4],v[5],.055,trim)
            for a,b in [(0,4),(1,4),(2,5),(3,5)]: self.beam(v[a],v[b],.026,trim)
        else:
            # The two thick slope slabs and full gable triangles are closed solids.
            for side in [-1,1]:
                e=x+side*w/2
                v=[(x,y-d/2,z+rise),(e,y-d/2,z),(e,y+d/2,z),(x,y+d/2,z+rise)]
                v+= [(a,b,c-.045) for a,b,c in v]
                self.part(v,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)] if side==1 else [(3,2,1,0),(4,5,6,7),(1,5,4,0),(2,6,5,1),(3,7,6,2),(0,4,7,3)],color)
            self.beam((x,y-d/2-.025,z+rise+.015),(x,y+d/2+.025,z+rise+.015),.058,trim)
            for yy in [y-d/2,y+d/2]:
                for side in [-1,1]: self.beam((x+side*w/2,yy,z),(x,yy,z+rise),.048,trim)
            if self.detail:
                for side in [-1,1]:
                    for f in [.34,.67]:
                        self.beam((x+side*w*f/2,y-d/2,z+rise*(1-f)+.007),(x+side*w*f/2,y+d/2,z+rise*(1-f)+.007),.013,trim)
    def wall_gable(self,x,y,z,w,d,h,rise,color):
        self.box((x,y,z+h/2),(w,d,h),color,bevel=.023)
        a=[(x-w/2,y-d/2,z+h),(x+w/2,y-d/2,z+h),(x,y-d/2,z+h+rise),
           (x-w/2,y+d/2,z+h),(x+w/2,y+d/2,z+h),(x,y+d/2,z+h+rise)]
        self.part(a,[(0,1,2),(5,4,3),(3,4,1,0),(4,5,2,1),(5,3,0,2)],color)
    def window(self,x,y,z,w=.22,h=.31,shutter=False,stone=False):
        frame='stonelight' if stone else 'woodlight'
        self.box((x,y-.008,z),(w+.045,.032,h+.047),'dark')
        self.box((x,y-.030,z),(w,.020,h),'glasslight')
        for dx in [-1,1]: self.box((x+dx*(w/2+.012),y-.057,z),(.029,.062,h+.074),frame)
        for dz in [-1,1]: self.box((x,y-.057,z+dz*(h/2+.012)),(w+.068,.062,.033),frame)
        if self.detail:
            self.box((x,y-.066,z),(.020,.020,h),frame)
            self.box((x,y-.066,z+.025),(w,.020,.018),frame)
        self.box((x,y-.070,z-h/2-.034),(w+.095,.115,.038),frame)
        if shutter:
            for dx in [-1,1]: self.box((x+dx*(w*.84),y-.030,z),(w*.40,.040,h+.025),'teal')
    def door(self,x,y,z,w=.24,h=.47,double=False):
        self.box((x,y-.011,z+h/2),(w+.075,.040,h+.04),'stonedark')
        self.box((x,y-.040,z+h/2),(w,.030,h),'timber')
        for dx in [-1,1]: self.box((x+dx*(w/2+.025),y-.060,z+h/2),(.046,.055,h+.08),'woodlight')
        self.box((x,y-.061,z+h+.016),(w+.100,.055,.055),'woodlight')
        self.box((x,y-.087,z-.014),(w+.14,.19,.065),'stonelight')
        if self.detail:
            for zz in [.23,.75]: self.box((x,y-.062,z+h*zz),(w,.018,.023),'iron')
            if double:self.box((x,y-.061,z+h/2),(.018,.030,h),'woodlight')
            self.box((x+w*.22,y-.073,z+h*.45),(.026,.022,.035),'brass')
    def chimney(self,x,y,z,h=.53,brick=False,w=.18):
        color='brick' if brick else 'stone'
        self.box((x,y,z+h/2),(w,w*.92,h),color,bevel=.014)
        self.box((x,y,z+h-.025),(w+.060,w+.055,.090),'stonelight')
        self.box((x,y,z+h+.025),(w*.65,w*.61,.009),'dark')
        if self.detail:
            for k in range(1,4):self.box((x,y-w*.465-.005,z+h*k/4),(w+.005,.010,.014),'stonelight')
    def barrel(self,x,y,z=.1):
        self.cylinder((x,y,z+.085),.090,.17,'wood',10,.075)
        if self.detail:
            for h in [.03,.14]:self.cylinder((x,y,z+h),.091,.019,'iron',10)
    def crate(self,x,y,z=.12,s=.18):
        self.box((x,y,z+s/2),(s,s,s),'wood')
        if self.detail:
            self.beam((x-s*.4,y-s*.52,z+.02),(x+s*.4,y-s*.52,z+s-.02),.025,'woodlight')
            for zz in [z+.025,z+s-.025]:self.box((x,y-s*.52,zz),(s,.018,.03),'woodlight')
    def hedge(self,x,y,z,w,d):
        self.box((x,y,z+.105),(w,d,.21),'green',bevel=.05)
        if self.detail:self.box((x-.02,y-.018,z+.195),(w*.86,d*.85,.05),'leaf',bevel=.025)

def frame(b,w,d,h,z=.12,levels=(.16,.78),braces=True):
    for zz in levels:b.box((0,0,z+zz*h),(w+.025,d+.03,.050),'timber')
    for x in [-w*.45,w*.45]:
        for y in [-d*.5,d*.5]:b.box((x,y,z+h/2),(.045,.045,h),'timber')
    if braces and b.detail:
        for side in [-1,1]:
            b.beam((side*w*.45,-d*.521,z+h*.77),(side*w*.22,-d*.521,z+h*.96),.038,'timber')

def foundation(b,w,d):
    b.box((0,0,.075),(w+.055,d+.055,.15),'stonedark',bevel=.03)
    b.box((0,0,.150),(w+.068,d+.068,.045),'stonelight',bevel=.02)

def cottage(b,variant=0):
    w,d,h=.94,.83,1.22
    foundation(b,w,d)
    b.wall_gable(0,0,.15,w,d,h,.53,'cream' if not variant else 'sage')
    frame(b,w,d,h)
    b.roof((0,0,h+.15),w+.14,d+.16,.56,'clay' if not variant else 'teal','claylight' if not variant else 'teallight')
    b.door(-.18,-d/2,.17,.24,.45)
    b.window(.23,-d/2,.64,.20,.31,True)
    b.window(0,-d/2,1.20,.19,.22)
    b.chimney(.28,.19,1.56,.58,variant==0)
    if b.detail:
        b.box((.26,-d/2-.13,.41),(.28,.13,.075),'wood')
        for x in [.18,.28,.34]: b.cylinder((x,-d/2-.13,.49),.035,.075,'leaf',6,.045)
        b.barrel(-.45,.31,.17)

def barn(b):
    w,d,h=1.02,.9,1.11
    foundation(b,w,d)
    b.wall_gable(0,0,.15,w,d,h,.65,'wood')
    frame(b,w,d,h,levels=(.06,.94))
    b.roof((0,0,h+.15),w+.13,d+.18,.68,'clay','claylight')
    b.door(0,-d/2,.17,.64,.85,True)
    if b.detail:
        for x in [-.43,-.32,.32,.43]:b.box((x,-d/2-.012,.79),(.013,.018,1.03),'woodlight')
        for side in [-1,1]:b.beam((side*.30,-d/2-.085,.25),(0,-d/2-.085,.94),.036,'woodlight')
    b.box((0,-d/2-.02,1.41),(.18,.04,.22),'dark')

def townhouse(b):
    w,d,h=.87,.82,1.67
    foundation(b,w,d)
    b.box((0,0,.62),(w*.86,d*.91,.92),'stone',bevel=.024)
    b.wall_gable(0,-.025,1.04,w,d,.75,.57,'ivory')
    frame(b,w,d,h,z=.14,levels=(.54,.96),braces=True)
    b.roof((0,-.025,1.80),w+.15,d+.17,.57,'teal','teallight')
    b.door(-.18,-d*.455,.17,.24,.58)
    b.window(.19,-d*.455,.68,.20,.36,stone=True)
    for x in [-.23,.23]:b.window(x,-d/2-.025,1.48,.22,.35)
    # A projecting balcony and supports create a distinct affluent silhouette.
    b.box((.22,-d/2-.155,1.19),(.42,.29,.055),'stonelight')
    b.box((.22,-d/2-.28,1.33),(.44,.035,.032),'brass')
    for x in [.03,.15,.28,.42]: b.box((x,-d/2-.28,1.255),(.019,.022,.15),'woodlight')
    b.chimney(-.27,.21,1.91,.60,True)

def manor(b):
    w,d,h=1.30,.89,1.57
    foundation(b,w,d)
    b.box((0,0,.15+h/2),(w,d,h),'ivory',bevel=.030)
    for zz in [.22,.94,1.64]:b.box((0,0,zz),(w+.05,d+.05,.075),'stonelight')
    for x in [-.60,.60]: b.box((x,-d/2-.013,.93),(.072,.071,1.42),'stone')
    b.roof((0,0,h+.15),w+.13,d+.15,.67,'teal','teallight',hip=True)
    for x in [-.42,.42]:
        b.window(x,-d/2,.63,.25,.38,stone=True)
        b.window(x,-d/2,1.27,.25,.36,stone=True)
    b.door(0,-d/2-.005,.17,.29,.57)
    # Door portico is genuinely open between the four thin posts.
    for x in [-.235,.235]:
        b.box((x,-d/2-.23,.57),(.052,.052,.83),'stonelight')
        b.box((x,-d/2-.23,.99),(.10,.10,.06),'stone')
    b.roof((0,-d/2-.12,1.02),.60,.43,.25,'teal','teallight')
    b.window(0,-d/2,1.37,.20,.26,stone=True)
    b.chimney(-.49,.20,1.89,.60,False,.19)
    b.chimney(.49,.20,1.89,.60,False,.19)
    if b.detail:
        for x in [-.55,.55]:b.hedge(x,-.59,.16,.29,.22)

def forge(b,workshop=False):
    w,d,h=1.0,.83,1.16 if not workshop else 1.39
    foundation(b,w,d)
    b.wall_gable(0,0,.15,w,d,h,.45,'salmon' if not workshop else 'blue')
    frame(b,w,d,h,levels=(.08,.88))
    b.roof((0,0,h+.15),w+.12,d+.13,.48,'slate' if not workshop else 'clay','slatelight' if not workshop else 'claylight')
    b.door(-.20,-d/2,.17,.32,.63,True)
    b.window(.26,-d/2,.93,.26,.24)
    # Industrial cap and buttressed flue carry the silhouette at map distance.
    b.box((.40,.23,.94),(.27,.26,1.58),'brick',bevel=.025)
    b.chimney(.40,.23,1.39,.81,True,.21)
    b.roof((-.10,-d/2-.24,.97),.87,.62,.15,'canvas','woodlight')
    for x in [-.46,.28]:b.box((x,-d/2-.48,.55),(.045,.045,.83),'timber')
    if b.detail:
        b.crate(.39,-.60,.17,.21)
        b.barrel(-.48,.32,.17)
        b.box((-.14,-.63,.24),(.22,.19,.15),'wood')
        b.box((-.14,-.63,.38),(.12,.10,.20),'iron')
        b.box((-.14,-.63,.49),(.29,.14,.075),'iron')
        b.part([(-.28,-.70,.45),(-.39,-.63,.47),(-.28,-.56,.45),(-.28,-.70,.51),(-.28,-.56,.51)],[(0,2,1),(0,1,3),(1,2,4),(3,1,4),(0,3,4,2)],'iron')

def modest(b,variant=0):
    w,d,h=.84,.80,1.38
    foundation(b,w,d)
    b.wall_gable(0,0,.15,w,d,h,.57,'plaster' if not variant else 'blue')
    frame(b,w,d,h,levels=(.08,.54,.96))
    b.roof((0,0,h+.15),w+.13,d+.15,.60,'clay' if not variant else 'slate','claylight' if not variant else 'slatelight')
    b.door(-.16,-d/2,.17,.23,.51)
    b.window(.21,-d/2,.65,.18,.26)
    b.window(-.04,-d/2,1.22,.27,.34,False)
    # Side lean-to is a sound, maintained addition, with no stigma/ruin coding.
    b.box((.45,.07,.47),(.28,.56,.64),'wood')
    b.roof((.45,.07,.81),.38,.66,.15,'clay','claylight')
    b.chimney(-.22,.20,1.74,.43,True,.16)
    if b.detail:
        b.box((.03,-d/2-.025,.91),(.69,.035,.046),'woodlight')
        b.barrel(-.38,.34,.17)
        # Small laundry bar is an ordinary residential use cue.
        b.beam((-.42,-.57,1.10),(.36,-.57,1.10),.013,'timber')
        for x,c in [(-.23,'ivory'),(.05,'sage')]:b.box((x,-.57,1.00),(.14,.017,.19),c)

def civic(b):
    w,d,h=1.15,.89,1.28
    foundation(b,w,d)
    b.wall_gable(0,0,.15,w,d,h,.62,'ivory')
    frame(b,w,d,h,levels=(.07,.62,.98))
    b.roof((0,0,h+.15),w+.16,d+.17,.66,'teal','teallight')
    b.door(0,-d/2,.17,.39,.63,True)
    for x in [-.39,.39]:b.window(x,-d/2,.81,.20,.43,stone=True)
    # Open cupola: four supports, hanging faceted bell, thick roof cap.
    b.box((0,.04,1.99),(.40,.40,.10),'stonelight')
    for x in [-.155,.155]:
        for y in [-.115,.195]:b.box((x,y,2.22),(.045,.045,.43),'woodlight')
    b.cylinder((0,.04,2.21),.115,.16,'brass',8,.07)
    b.roof((0,.04,2.46),.54,.54,.26,'teal','teallight',hip=True)
    b.beam((0,.04,2.69),(0,.04,2.99),.019,'brass')
    b.part([(0,.037,2.98),(.25,.037,2.91),(0,.037,2.82),(0,.043,2.98),(.25,.043,2.91),(0,.043,2.82)],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)],'clay')

def well(b):
    n=12
    b.cylinder((0,0,.04),.44,.08,'stonedark',n)
    b.cylinder((0,0,.09),.40,.04,'stonelight',n)
    for k in range(n):
        # Exact annular wedge blocks: no overlapping coplanar box tops, which
        # create dark self-shadow wedges in an otherwise open stone rim.
        a0=2*math.pi*(k-.5)/n;a1=2*math.pi*(k+.5)/n
        ring=[(.22*math.cos(a0),.22*math.sin(a0)),(.36*math.cos(a0),.36*math.sin(a0)),
              (.36*math.cos(a1),.36*math.sin(a1)),(.22*math.cos(a1),.22*math.sin(a1))]
        v=[(x,y,z) for z in [.105,.375] for x,y in ring]
        b.part(v,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'stone' if k%3 else 'stonelight')
    b.cylinder((0,0,.15),.25,.018,'water',n)
    for x in [-.40,.40]:b.box((x,0,.56),(.072,.075,1.0),'timber')
    b.roof((0,0,1.06),1.05,.65,.29,'clay','claylight')
    b.beam((-.41,0,.74),(.48,0,.74),.07,'woodlight')
    b.beam((.48,0,.74),(.48,0,.57),.035,'iron')
    if b.detail:
        b.beam((0,0,.72),(0,0,.22),.012,'canvas')
        b.cylinder((.27,-.22,.40),.065,.12,'wood',8,.075)

def garden(b):
    b.box((0,0,.04),(1.03,.95,.08),'stonedark',bevel=.06)
    b.box((0,0,.084),(.99,.91,.02),'soil',bevel=.06)
    for x in [-.34,.34]:
        for y in [-.28,.28]:b.hedge(x,y,.10,.26,.27)
    b.box((0,0,.098),(.23,.92,.02),'stonelight')
    b.box((0,0,.100),(.98,.17,.02),'stonelight')
    b.cylinder((0,0,.15),.15,.10,'stone',10,.18)
    b.cylinder((0,0,.206),.13,.012,'water',10)
    if b.detail:
        for x,y in [(-.34,-.28),(.34,.28),(-.34,.28),(.34,-.28)]:
            b.cylinder((x,y,.38),.028,.08,'flower',6,.065)

def yard(b):
    b.box((0,0,.025),(1,.83,.05),'stonedark',bevel=.04)
    for x in [-.41,.41]: b.box((x,.32,.24),(.045,.045,.46),'timber')
    for h in [.16,.35]:b.box((0,.32,h),(.89,.037,.052),'woodlight')
    b.crate(-.24,.15,.05,.27);b.crate(.035,.12,.05,.21)
    b.crate(-.22,.14,.32,.18);b.barrel(.32,.18,.04)
    for x in [-.25,-.10,.05,.20]: b.beam((x,-.28,.11),(x+.04,.01,.11),.095,'wood')
    if b.detail:
        b.box((.24,-.22,.29),(.30,.25,.08),'woodlight')
        for x in [.11,.36]:b.box((x,-.22,.17),(.034,.17,.24),'wood')

# All modules are original, independent kit pieces. Optional props are separate
# assets rather than a city-wide prefab, so a one-hex settlement stays one hex.
SPECS=[
 ('village_cottage_a','village',lambda b:cottage(b,0),.51,1.12),
 ('village_cottage_b','village',lambda b:cottage(b,1),.51,1.12),
 ('village_barn','village',barn,.54,1.12),
 ('shared_well','shared',well,.34,.53),
 ('rich_manor','rich',manor,.55,1.29),
 ('rich_townhouse','rich',townhouse,.53,1.36),
 ('industrial_forge','industrial',lambda b:forge(b,False),.55,1.25),
 ('industrial_workshop','industrial',lambda b:forge(b,True),.55,1.28),
 ('poor_home_a','poor',lambda b:modest(b,0),.50,1.13),
 ('poor_home_b','poor',lambda b:modest(b,1),.50,1.13),
 ('civic_hall','civic',civic,.55,1.50),
 ('garden_court','rich',garden,.39,.22),
 ('workyard','industrial',yard,.38,.24),
]

def material():
    mat=bpy.data.materials.new('CityDistrictPalette-vcol')
    mat.use_nodes=True
    mat.use_backface_culling=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Roughness'].default_value=.91
    bsdf.inputs['Metallic'].default_value=0
    bsdf.inputs['Specular IOR Level'].default_value=.20
    vc=mat.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='CityColor'
    mat.node_tree.links.new(vc.outputs['Color'],bsdf.inputs['Base Color'])
    mat.diffuse_color=(.7,.6,.45,1)
    return mat

def make_mesh(builder,mat,width,height,reference_bounds=None):
    v=builder.v
    lo=[min(p[i] for p in v) for i in range(3)];hi=[max(p[i] for p in v) for i in range(3)]
    if reference_bounds:lo,hi=reference_bounds
    scale=width/max(hi[0]-lo[0],hi[1]-lo[1])
    sz=height/(hi[2]-lo[2]);cx=(hi[0]+lo[0])/2;cy=(hi[1]+lo[1])/2
    # Turn the authoring front (-Y) to +Y before glTF Y-up conversion: Godot front -Z.
    verts=[(-(x-cx)*scale,-(y-cy)*scale,(z-lo[2])*sz) for x,y,z in v]
    mesh=bpy.data.meshes.new(builder.name)
    mesh.from_pydata(verts,[],builder.f);mesh.update()
    attr=mesh.color_attributes.new(name='CityColor',type='FLOAT_COLOR',domain='CORNER')
    for poly,col in zip(mesh.polygons,builder.c):
        poly.use_smooth=False
        for li in poly.loop_indices:attr.data[li].color=col
    mesh.materials.append(mat)
    obj=bpy.data.objects.new(builder.name,mesh)
    bpy.context.collection.objects.link(obj)
    # Explicit normals are kept flat. Single mesh/material gives one draw surface.
    mesh.calc_loop_triangles()
    return obj,{'triangles':len(mesh.loop_triangles),'vertices_authored':len(mesh.vertices),
                'faces_authored':len(mesh.polygons),'materials':1},[lo,hi]

def export(obj,path):
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
    bpy.context.view_layer.objects.active=obj
    temp_path=path.parent/('.'+path.stem+'.pending.glb')
    bpy.ops.export_scene.gltf(filepath=str(temp_path),export_format='GLB',use_selection=True,
      export_yup=True,export_apply=True,export_animations=False,export_cameras=False,
      export_lights=False,export_texcoords=False,export_normals=True,
      export_vertex_color='MATERIAL',export_all_vertex_colors=False,
      export_materials='EXPORT',export_extras=True)
    # Rebuilding one corrected module should not touch unchanged engine imports.
    if path.exists() and path.read_bytes()==temp_path.read_bytes():temp_path.unlink()
    else:temp_path.replace(path)

def setup_preview(objects):
    # Asset contact sheet has no dependency on the game's world or renderer.
    scene=bpy.context.scene
    for idx,obj in enumerate(objects):
        obj.location=((idx%5)*1.10,(idx//5)*1.32,0)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.022))
    floor=bpy.context.object;floor.name='PreviewOnly_Ground'
    m=bpy.data.materials.new('PreviewOnly_Parchment');m.diffuse_color=(.24,.30,.26,1);m.use_nodes=True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.24,.30,.26,1)
    m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=1
    floor.data.materials.append(m)
    bpy.ops.object.light_add(type='AREA',location=(-3,-4,8));sun=bpy.context.object
    sun.data.energy=900;sun.data.size=6;sun.rotation_euler=(Vector((2,1,0))-sun.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add(location=(7.1,10,8.0));cam=bpy.context.object
    target=Vector((2.16,1.30,.56));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO';cam.data.ortho_scale=7.05;scene.camera=cam
    scene.world=bpy.data.worlds.new('PreviewOnly_World')
    scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.55,.66,.77,1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.6
    scene.render.engine='CYCLES';scene.cycles.samples=16
    scene.cycles.use_denoising=False;scene.render.threads_mode='FIXED';scene.render.threads=2
    scene.render.resolution_x=1800;scene.render.resolution_y=1160;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='Standard';scene.view_settings.look='None'
    scene.view_settings.exposure=0;scene.view_settings.gamma=1
    scene.render.image_settings.file_format='PNG'
    scene.render.filepath=str(ROOT/'previews'/'kit_contactsheet_raw.png')

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for d in ['models','lod1','source','previews']:(ROOT/d).mkdir(exist_ok=True)
    mat=material();rows=[];objects=[]
    for name,district,fn,width,height in SPECS:
        b=Builder(name,True);fn(b);obj,stats,bounds=make_mesh(b,mat,width,height)
        obj['asset_id']=name;obj['district']=district;obj['visual_only']=True
        obj['kit_version']='city_districts/v1';obj['forward']='-Z in Godot'
        model=ROOT/'models'/f'{name}.glb';export(obj,model);objects.append(obj)
        mins=[min(v.co[i] for v in obj.data.vertices) for i in range(3)]
        maxs=[max(v.co[i] for v in obj.data.vertices) for i in range(3)]
        # Blender (x,y,z) -> Godot/glTF (x,z,-y).
        aabb_min=[mins[0],mins[2],-maxs[1]];aabb_max=[maxs[0],maxs[2],-mins[1]]
        footprint=[maxs[0]-mins[0],maxs[1]-mins[1]]
        lod_builder=Builder(name+'_lod1',False);fn(lod_builder)
        lo,lo_stats,_=make_mesh(lod_builder,mat,width,height,bounds)
        lodfile=ROOT/'lod1'/f'{name}_lod1.glb';export(lo,lodfile)
        bpy.data.objects.remove(lo,do_unlink=True)
        rows.append({'id':name,'district':district,'glb':f'models/{name}.glb',
          'lod1_glb':f'lod1/{name}_lod1.glb','aabb_min_xyz':aabb_min,'aabb_max_xyz':aabb_max,
          'footprint_xz':footprint,'footprint_radius':math.hypot(*footprint)/2,
          'height':aabb_max[1],'pivot':'ground center, Y=0','forward':'-Z',
          'ground_collision':'none; footprint is advisory, not an authored rule blocker',
          'lod0':stats,'lod1':lo_stats,'sha256':hashlib.sha256(model.read_bytes()).hexdigest(),
          'lod1_sha256':hashlib.sha256(lodfile.read_bytes()).hexdigest()})
    manifest={'schema':'city_district_kit/v1','generator':'Blender '+bpy.app.version_string,
      'authorship':'Original mesh and palette. No third-party geometry, textures, or code copied.',
      'scale_contract':'pointy hex radius1; village/city-state one hex, largest city initially3; compact district pockets',
      'material':'one rough opaque vertex-color material per mesh; COLOR_0 uses scene-linear values',
      'physics_nodes':0,'textures':0,'assets':rows,
      'totals':{'lod0_triangles':sum(r['lod0']['triangles'] for r in rows),
                'lod1_triangles':sum(r['lod1']['triangles'] for r in rows)}}
    (ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    setup_preview(objects)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source'/'city_district_kit.blend'))
    if '--render' in sys.argv:bpy.ops.render.render(write_still=True)
    print('CITY_KIT_COMPLETE',json.dumps(manifest['totals']))

if __name__=='__main__':main()
