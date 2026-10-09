#!/usr/bin/env python3
"""Read-only, stdlib source proof for authored creative-bracing geometry.

The source JSON and binary mesh are pinned. This verifies source-bound claims,
not native readability, arbitrary language understanding or the game executor.
No artifact is written unless --out explicitly names a report file.
"""
from __future__ import annotations
import argparse
import gzip
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def resource(path):
    assert path.startswith('res://') and '..' not in path
    return ROOT / path[6:]

def clip(poly, axis, sign, bound):
    out = []
    for p, q in zip(poly, poly[1:] + poly[:1]):
        pin, qin = sign * p[axis] <= bound, sign * q[axis] <= bound
        if pin:
            out.append(p)
        if pin != qin:
            t = (bound - sign * p[axis]) / (sign * (q[axis] - p[axis]))
            out.append(tuple(p[k] + t * (q[k] - p[k]) for k in (0, 1)))
    return out

def area(poly):
    return abs(sum(a[0] * b[1] - a[1] * b[0] for a, b in zip(poly, poly[1:] + poly[:1]))) / 2

def local(point, center, xaxis):
    dx, dz = point[0] - center[0], point[1] - center[1]
    return dx * xaxis[0] + dz * xaxis[1], dx * -xaxis[1] + dz * xaxis[0]

def overlap(polygons, center, xaxis, xmin, xmax, zmin, zmax):
    total = 0.0
    for polygon in polygons:
        poly = [local(q, center, xaxis) for q in polygon]
        for axis, sign, bound in [(0, -1, -xmin), (0, 1, xmax), (1, -1, -zmin), (1, 1, zmax)]:
            poly = clip(poly, axis, sign, bound)
            if not poly:
                break
        total += area(poly)
    return total

def segment_box(a, b, xmin, xmax, zmin, zmax):
    low, high = 0.0, 1.0
    for i, lo, hi in [(0, xmin, xmax), (1, zmin, zmax)]:
        delta = b[i] - a[i]
        if abs(delta) < 1e-12:
            if not lo < a[i] < hi:
                return False
        else:
            l, h = sorted(((lo - a[i]) / delta, (hi - a[i]) / delta))
            low, high = max(low, l), min(high, h)
    return high - low > 1e-8

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    text = (ROOT / 'view/playable_build/creative_content.gd').read_text()
    authored = json.loads(text.split("const DATA := '''", 1)[1].split("'''", 1)[0])
    bundle = json.loads((ROOT / 'artifacts/world_bundle_20261002/manifest.json').read_text())
    checks = []
    def check(ok, label):
        checks.append({'check': label, 'passed': bool(ok)})
    check(authored['bundle_id'] == bundle['bundle_id'], 'authored catalog binds source bundle')
    for authored_key, member in [('source_catalog_sha256', 'catalog'), ('source_navigation_sha256', 'navigation'), ('source_topology_sha256', 'source_topology')]:
        row = bundle['runtime'][member]
        check(authored[authored_key] == row['sha256'] == digest(resource(row['path'])), member + ' hash is exact')
    check(authored['source_mesh_sha256'] == bundle['source_identity']['mesh_sha256'], 'source mesh identity exact')
    catalog = json.loads(resource(bundle['runtime']['catalog']['path']).read_text())
    cells = {(c['q'], c['r']): c for c in catalog['cells']}
    nav = json.loads(resource(bundle['runtime']['navigation']['path']).read_text())['allowed_neighbors']
    topology = json.loads(gzip.decompress(resource(bundle['runtime']['source_topology']['path']).read_bytes()))
    vertices = [v['position'] for v in topology['vertices']]
    water_member = bundle['runtime']['physical_water']
    check(digest(resource(water_member['path'])) == water_member['sha256'], 'physical water union hash exact')
    water = [p['polygon_xz'] for p in json.loads(resource(water_member['path']).read_text())['polygons']]
    mountain_member = bundle['runtime']['mountain_manifest']
    check(digest(resource(mountain_member['path'])) == mountain_member['sha256'], 'mountain manifest hash exact')
    mountain = json.loads(resource(mountain_member['path']).read_text())
    binary = resource(mountain_member['path']).parent / mountain['binary']
    check(digest(binary) == mountain['binary_sha256'], 'rendered mountain binary hash exact')
    values = struct.unpack('<' + 'f' * (mountain['vertices'] * 8), gzip.decompress(binary.read_bytes()))
    mountains = [[(values[i], values[i + 2]) for i in (j, j + 8, j + 16)] for j in range(0, len(values), 24)]
    reserved = {(-3, 17), (-3, 16), (-2, 16), (-4, 15), (-6, 17), (-3, 15), (-6, 16)}
    targets = []
    for target_id, target in authored['passage_targets'].items():
        geo = authored['geometry'][target_id]
        endpoints = [tuple(h) for h in target['endpoints']]
        a, b = [cells[h] for h in endpoints]
        ka, kb = [f'{h[0]},{h[1]}' for h in endpoints]
        check(endpoints == sorted(endpoints), target_id + ': canonical endpoint ordering')
        check(not reserved.intersection(endpoints), target_id + ': separate from settlement/gate cells')
        check(all(c['walkable'] and c['dry_fraction'] >= .99999 for c in [a, b]), target_id + ': both cells fully dry/walkable')
        check(kb in nav[ka] and ka in nav[kb], target_id + ': actual source navigation edge open both ways')
        check(target['support_hex'] in target['endpoints'], target_id + ': approach is genuine endpoint')
        check(a['support']['source_face_index'] == target['source_support']['from_face_index'] and b['support']['source_face_index'] == target['source_support']['to_face_index'], target_id + ': endpoint source faces exact')
        samples = [geo['center'], geo['loose_ground']] + geo['contact_ground'] + geo['cheek_ground'] + geo['loose_footprint_support']
        max_error = 0.0
        for sample in samples:
            face = topology['faces'][sample['source_face_index']]
            check(face['id'] == sample['source_face_id'], target_id + ': sample stable source face ID')
            weights = sample['barycentric']
            check(min(weights) >= -1e-8 and abs(sum(weights) - 1) < 1e-8, target_id + ': sample lies inside source triangle')
            reconstructed = [sum(vertices[face['vertices'][i]][axis] * weights[i] for i in range(3)) for axis in range(3)]
            error = max(abs(reconstructed[i] - sample['position'][i]) for i in range(3))
            max_error = max(max_error, error)
        check(max_error < 1e-8, target_id + ': all contact/loose/cheek heights rederive barycentrically')
        pa, pb = a['support']['position'], b['support']['position']
        norm = math.hypot(pb[0] - pa[0], pb[2] - pa[2])
        direction = ((pb[0] - pa[0]) / norm, (pb[2] - pa[2]) / norm)
        corridor_mountain = overlap(mountains, (pa[0], pa[2]), direction, -.3, norm + .3, -.8, .8)
        check(corridor_mountain < 1e-9, target_id + ': broad entire source corridor clears all rendered mountain triangles')
        frame = target['pose_frames']['loose']
        cx, _, cz = [v * .0005 for v in frame['origin_mm']]
        yaw = frame['yaw_milliradians'] / 1000
        loose_axis = (math.cos(yaw), -math.sin(yaw))
        loose_water = overlap(water, (cx, cz), loose_axis, -.475, .475, -.045, .045)
        loose_mountain = overlap(mountains, (cx, cz), loose_axis, -.475, .475, -.045, .045)
        check(loose_water < 1e-9 and loose_mountain < 1e-9, target_id + ': full longest/widest loose-object footprint is dry and mountain-free')
        max_ground = max(p['position'][1] for p in geo['loose_footprint_support'])
        underside = frame['origin_mm'][1] * .0005 - authored['render_policy']['pose_vertical_reference_mm'] * .0005
        check(0 <= underside - max_ground <= .0005, target_id + ': fixed loose underside rests on highest verified support within 0.5 mm world quantization')
        brace = target['pose_frames']['braced']; center = (brace['origin_mm'][0] * .0005, brace['origin_mm'][2] * .0005)
        yaw = brace['yaw_milliradians'] / 1000; axis = (math.cos(yaw), -math.sin(yaw))
        walls_water = sum(overlap(water, center, axis, lo, hi, -.12, .12) for lo, hi in [(-.61, -.30), (.30, .61)])
        check(walls_water < 1e-9, target_id + ': visible stone-cheek footprints clear physical water')
        crossed = []
        for key, neighbors in nav.items():
            h = tuple(int(v) for v in key.split(','))
            if h not in cells or 'support' not in cells[h]: continue
            for neighbor in neighbors:
                if key >= neighbor or {key, neighbor} == {ka, kb}: continue
                other = tuple(int(v) for v in neighbor.split(','))
                if other not in cells or 'support' not in cells[other]: continue
                p, q = cells[h]['support']['position'], cells[other]['support']['position']
                l, r = local((p[0], p[2]), center, axis), local((q[0], q[2]), center, axis)
                if any(segment_box(l, r, lo, hi, -.12, .12) for lo, hi in [(-.61, -.30), (.30, .61)]): crossed.append([key, neighbor])
        check(not crossed, target_id + ': masonry does not intersect any unrelated source navigation segment')
        for profile_id, profile in authored['item_profiles'].items():
            physical = profile['physical_traits']
            check(physical['length_mm'] >= target['width_mm'] + 200 and target['min_section_mm'] <= physical['section_mm'] <= target['max_section_mm'] and physical['bearing'] >= target['required_bearing'] and physical['rigidity'] >= 2 and physical['mass_g'] <= 6000, target_id + ': compatible authored dimensions/classes ' + profile_id)
        targets.append({'id': target_id, 'endpoints': target['endpoints'], 'support_hex': target['support_hex'], 'barycentric_max_error_world': max_error, 'mountain_corridor_overlap_area': corridor_mountain, 'loose_water_overlap_area': loose_water, 'loose_mountain_overlap_area': loose_mountain, 'masonry_water_overlap_area': walls_water, 'unrelated_navigation_intersections': crossed})
    report = {'passed': all(c['passed'] for c in checks), 'checks': len(checks), 'failures': [c['check'] for c in checks if not c['passed']], 'bundle_id': bundle['bundle_id'], 'source_mesh_sha256': authored['source_mesh_sha256'], 'rendered_mountain_triangles': len(mountains), 'water_polygons': len(water), 'targets': targets, 'scope': 'Static source geometry only; native screenshots and actual action execution are separate tests.'}
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    raise SystemExit(0 if report['passed'] else 1)

if __name__ == '__main__':
    main()
