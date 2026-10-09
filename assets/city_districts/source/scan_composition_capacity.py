"""Read-only placement-capacity study. Does not modify world or renderer files.

Uses the exact source support anchors and authored road/boundary polylines.
Outputs an advisory composition report, never new authoritative settlement data.
"""
import json
import math
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
GAME=ROOT.parent.parent
manifest=json.loads((GAME/'artifacts/settlement_20261003/content_v1.json').read_text())
catalog=json.loads((GAME/'artifacts/world_bundle_20261002/world_catalog.json').read_text())
navigation=json.loads((GAME/'artifacts/world_bundle_20261002/navigation.json').read_text())
assets={a['id']:a for a in json.loads((ROOT/'manifest.json').read_text())['assets']}
supports={(c['q'],c['r']):c['support']['position'] for c in catalog['cells'] if c.get('support')}

def xz(p):return (p[0],p[2])
def distance(a,b):return math.hypot(a[0]-b[0],a[1]-b[1])
def segment_distance(p,a,b):
    d=(b[0]-a[0],b[1]-a[1]);l=d[0]**2+d[1]**2
    t=max(0,min(1,((p[0]-a[0])*d[0]+(p[1]-a[1])*d[1])/max(l,1e-12)))
    return distance(p,(a[0]+t*d[0],a[1]+t*d[1]))
def inside(p,edges):
    crossings=0
    for a,b in edges:
        if (a[1]>p[1])==(b[1]>p[1]):continue
        crossx=a[0]+(p[1]-a[1])*(b[0]-a[0])/(b[1]-a[1])
        crossings+=int(crossx>p[0])
    return crossings%2==1
def hex_edges(h):
    center=(math.sqrt(3)*(h[0]+h[1]/2),h[1]*1.5)
    v=[(center[0]+math.cos(math.pi/6+i*math.pi/3),center[1]+math.sin(math.pi/6+i*math.pi/3)) for i in range(6)]
    return [(v[i],v[(i+1)%6])for i in range(6)]

recipes={
 'affluent':[('rich_manor',.255),('rich_townhouse',.205),('garden_court',.105)],
 'industrial':[('industrial_forge',.235),('industrial_workshop',.200),('village_barn',.170),('workyard',.105)],
 'modest':[('poor_home_a',.220),('poor_home_b',.190),('poor_home_a',.165),('poor_home_b',.145),('shared_well',.085)],
 'rural':[('village_cottage_a',.180),('village_barn',.150),('village_cottage_b',.130),('shared_well',.075)],
 'civic':[('civic_hall',.220),('rich_townhouse',.180),('rich_townhouse',.160),('poor_home_a',.150),('garden_court',.085)],
}

candidate_cache={}

def backtracking_pack(candidates, recipe, occupied=(), max_states=10000):
    """Small finite search for compact one-district groups; preserve plan sizes.

    Candidate order is capacity-descending then x/z ascending. Count only legal
    partial states, and use a forward feasibility check before deeper recursion.
    """
    options=[[c for c in candidates if c['capacity']>=r]for _,r in recipe]
    states=0;candidate_visits=0
    def legal(c,r,placed):
        return all(distance(c['p'],p['position_xz'])>=r+p['radius']+.035 for p in placed)
    def search(stage,placed):
        nonlocal states,candidate_visits
        if stage==len(recipe):return placed[len(occupied):]
        asset,radius=recipe[stage]
        for c in options[stage]:
            candidate_visits+=1
            if not legal(c,radius,placed):continue
            states+=1
            if states>max_states:return None
            next_placed=placed+[{'asset':asset,'position_xz':list(c['p']),'radius':radius,'route':c['route']}]
            if not all(any(legal(f,recipe[j][1],next_placed)for f in options[j])for j in range(stage+1,len(recipe))):continue
            result=search(stage+1,next_placed)
            if result is not None:return result
        return None
    selected=search(0,list(occupied))
    return selected,states,candidate_visits

def study(site):
    edges=[(xz(e['a']),xz(e['b']))for e in site['wall_edges']]
    anchors=[xz(supports[tuple(h)])for h in site['interior_hexes']]
    routes=[(xz(a),xz(b))for a,b in zip(site['road_points'],site['road_points'][1:])]
    for i,a in enumerate(site['interior_hexes']):
        for j,b in enumerate(site['interior_hexes'][:i]):
            dq,dr=a[0]-b[0],a[1]-b[1]
            if max(abs(dq),abs(dr),abs(dq+dr))==1:routes.append((anchors[i],anchors[j]))
    if not site.get('walled'):
        for h in site['interior_hexes']:
            key=f'{h[0]},{h[1]}'
            for n in navigation['allowed_neighbors'].get(key,[]):
                neighbor=tuple(map(int,n.split(',')))
                routes.append((xz(supports[tuple(h)]),xz(supports[neighbor])))
    low=(min(p[0]for edge in edges for p in edge),min(p[1]for edge in edges for p in edge))
    high=(max(p[0]for edge in edges for p in edge),max(p[1]for edge in edges for p in edge))
    candidates=[]
    wall_width=site['wall_thickness'] if site.get('walled') else 0
    for ix in range(math.floor(low[0]*40),math.ceil(high[0]*40)+1):
        for iy in range(math.floor(low[1]*40),math.ceil(high[1]*40)+1):
            p=(ix/40,iy/40)
            if not inside(p,edges):continue
            clearance=min([distance(p,a)for a in anchors]+[segment_distance(p,a,b)for a,b in routes])
            boundary=min(segment_distance(p,a,b)for a,b in edges)-wall_width/2
            capacity=min(clearance-.26,boundary-.055)
            if capacity>=.065:candidates.append({'p':p,'capacity':capacity,'route':clearance})
    candidates.sort(key=lambda c:(-c['capacity'],c['p'][0],c['p'][1]))
    candidate_cache[site["site_kind"]]=candidates
    placed=[];missing=[]
    if site['site_kind']=='village':
        selection,states,candidate_visits=backtracking_pack(candidates,recipes['rural'])
        for p in selection or []:
            fit=p['radius']*.95/assets[p['asset']]['footprint_radius']
            placed.append({'asset':p['asset'],'district':'rural','position_xz':p['position_xz'],
              'radius':p['radius'],'route_clearance_after_footprint':p['route']-p['radius'],
              'uniform_scale':round(fit,5),'roof_height':round(assets[p['asset']]['height']*fit,5)})
        if selection is None:missing=[{'reason':'No complete placement within bounded search'}]
        return {'site_kind':site['site_kind'],'hex_count':len(site['interior_hexes']),
          'candidates':len(candidates),'placed':placed,'missing':missing,'search_states':states,'candidate_visits':candidate_visits,
          'all_allowed_neighbor_spokes_reserved':True,
          'roofs':sum(assets[p['asset']]['height']>.7 for p in placed),
          'props':sum(assets[p['asset']]['height']<=.7 for p in placed)}
    # Give every district its main roof first, then progressively fill pockets.
    for stage in range(5):
        for district in site['districts']:
            recipe=recipes[district['architectural_kit']]
            if stage>=len(recipe):continue
            asset,radius=recipe[stage]
            local=[c for c in candidates if c['capacity']>=radius and any(inside(c['p'],hex_edges(h))for h in district['support_hexes'])]
            legal=[c for c in local if all(distance(c['p'],p['position_xz'])>=radius+p['radius']+.035 for p in placed)]
            if not legal:
                missing.append({'asset':asset,'stage':stage,'radius':radius,'district':district['architectural_kit']});continue
            # Exact maximum-clearance ordering mirrors the existing renderer.
            c=legal[0];fit=radius*.95/assets[asset]['footprint_radius']
            placed.append({'asset':asset,'district':district['architectural_kit'],'position_xz':list(c['p']),
              'radius':radius,'route_clearance_after_footprint':c['route']-radius,
              'uniform_scale':round(fit,5),'roof_height':round(assets[asset]['height']*fit,5)})
    return {'site_kind':site['site_kind'],'hex_count':len(site['interior_hexes']),
      'candidates':len(candidates),'placed':placed,'missing':missing,
      'roofs':sum(assets[p['asset']]['height']>.7 for p in placed),
      'props':sum(assets[p['asset']]['height']<=.7 for p in placed)}

report={'schema':'city_composition_capacity_advisory/v1','authority_modified':False,
  'route_clearance':.26,'building_gap':.035,'candidate_grid':.025,
  'caveat':'Circles include all overhangs. All village allowed-neighbor spokes included. Open gate leaf exclusion must be checked by runtime. Not runtime or terrain-height QA.',
  'staged_recipes':recipes,'selection':'capacity descending, x/z ascending; small bounded backtracking for village, staged greedy elsewhere',
  'sites':[study(s)for s in [manifest]+manifest.get('additional_settlements',[])]}
(ROOT/'composition_capacity.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
