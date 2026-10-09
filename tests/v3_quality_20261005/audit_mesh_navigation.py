#!/usr/bin/env python3
"""Read-only independent oracle over actual emitted ArrayMesh triangles.

No terrain_field/generator reproduction and no face-owner trust. Geometry is
indexed only by triangle XZ bounds; coverage is a union, never an interval sum.
Expected navigation JSON: {source_hash,supported,support_heights,allowed,spawn}.
This proves triangle dry support, not collision footprint or slope permission.
"""
import argparse
import collections
import hashlib
import json
import math
import struct
from pathlib import Path

DIRECTIONS = ((1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1))
GEOMETRY_EPS = 1e-7
COVERAGE_EPS = 2e-6
HEIGHT_EPS = 2e-5


def axial_center(key):
    q, r = map(int, key.split(','))
    return math.sqrt(3) * (q + r / 2), 1.5 * r


def barycentric(point, tri):
    x, z = point
    (ax, _, az), (bx, _, bz), (cx, _, cz) = tri
    determinant = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
    if abs(determinant) < 1e-14:
        return None
    a = ((bz - cz) * (x - cx) + (cx - bx) * (z - cz)) / determinant
    b = ((cz - az) * (x - cx) + (ax - cx) * (z - cz)) / determinant
    return a, b, 1 - a - b


def segment_interval(start, end, tri):
    """Clip barycentric affine coordinates along the segment to all three >=0."""
    b0, b1 = barycentric(start, tri), barycentric(end, tri)
    if b0 is None:
        return None
    low, high = 0.0, 1.0
    for initial, final in zip(b0, b1):
        delta = final - initial
        if abs(delta) <= 1e-14:
            if initial < -GEOMETRY_EPS:
                return None
            continue
        boundary = -initial / delta
        if delta > 0:
            low = max(low, boundary)
        else:
            high = min(high, boundary)
        if low > high + GEOMETRY_EPS:
            return None
    low, high = max(0.0, low), min(1.0, high)
    if high - low < 1e-10:
        return None
    return low, high


def height(point, tri):
    values = barycentric(point, tri)
    return sum(b * p[1] for b, p in zip(values, tri))


class MeshOracle:
    def __init__(self, triangles, water_level=0.0, clearance=0.0001):
        self.triangles = triangles
        self.water_level = water_level
        self.clearance = clearance
        self.bucket_size = 2.0
        self.buckets = collections.defaultdict(set)
        for index, tri in enumerate(triangles):
            if len(tri) != 3 or any(len(p) != 3 or not all(math.isfinite(v) for v in p) for p in tri):
                raise ValueError('Malformed/nonfinite actual triangle')
            if barycentric((tri[0][0], tri[0][2]), tri) is None:
                raise ValueError('Degenerate actual triangle')
            for bucket in self._buckets(min(p[0] for p in tri), max(p[0] for p in tri), min(p[2] for p in tri), max(p[2] for p in tri)):
                self.buckets[bucket].add(index)

    def _buckets(self, minx, maxx, minz, maxz):
        for x in range(math.floor((minx - GEOMETRY_EPS) / self.bucket_size), math.floor((maxx + GEOMETRY_EPS) / self.bucket_size) + 1):
            for z in range(math.floor((minz - GEOMETRY_EPS) / self.bucket_size), math.floor((maxz + GEOMETRY_EPS) / self.bucket_size) + 1):
                yield x, z

    def candidates(self, start, end):
        result = set()
        for bucket in self._buckets(min(start[0], end[0]), max(start[0], end[0]), min(start[1], end[1]), max(start[1], end[1])):
            result.update(self.buckets.get(bucket, ()))
        return sorted(result)

    def anchor(self, point):
        heights = []
        for index in self.candidates(point, point):
            tri = self.triangles[index]
            values = barycentric(point, tri)
            if min(values) >= -GEOMETRY_EPS:
                heights.append(height(point, tri))
        return {'covered': bool(heights), 'dry': bool(heights) and min(heights) > self.water_level + self.clearance,
                'height_min': min(heights) if heights else None, 'height_max': max(heights) if heights else None,
                'continuous': bool(heights) and max(heights) - min(heights) <= HEIGHT_EPS}

    def segment(self, start, end):
        intervals, min_height = [], math.inf
        for index in self.candidates(start, end):
            tri = self.triangles[index]
            interval = segment_interval(start, end, tri)
            if interval is None:
                continue
            intervals.append(interval)
            for t in interval:
                p = (start[0] + t * (end[0] - start[0]), start[1] + t * (end[1] - start[1]))
                min_height = min(min_height, height(p, tri))
        merged = []
        for low, high in sorted(intervals):
            if not merged or low > merged[-1][1] + COVERAGE_EPS:
                merged.append([low, high])
            else:
                merged[-1][1] = max(merged[-1][1], high)
        covered = len(merged) == 1 and merged[0][0] <= COVERAGE_EPS and merged[0][1] >= 1 - COVERAGE_EPS
        return {'covered': covered, 'dry': covered and min_height > self.water_level + self.clearance,
                'minimum_height': min_height if intervals else None, 'coverage': merged, 'intervals': len(intervals)}


def audit(mesh, nav=None):
    oracle = MeshOracle(mesh['triangles'], float(mesh.get('water_level', 0)), float((nav or {}).get('clearance', 0.0001)))
    domain = mesh['hexes']
    anchors = {key: oracle.anchor(axial_center(key)) for key in sorted(domain)}
    edges = {}
    for key in sorted(domain):
        q, r = map(int, key.split(','))
        for dq, dr in DIRECTIONS:
            other = f'{q+dq},{r+dr}'
            if other in domain and key < other:
                edges[(key, other)] = oracle.segment(axial_center(key), axial_center(other))
    errors, conservative = [], []
    digest = hashlib.sha256()
    for triangle in mesh['triangles']:
        for vertex in triangle:
            digest.update(struct.pack('<3f', *vertex))
    if digest.hexdigest() != mesh.get('canonical_geometry_hash'):
        errors.append('Exported triangle bytes differ from declared actual geometry hash')
    if 'vertices' in mesh and 'indices' in mesh:
        indexed = [mesh['vertices'][i] for i in mesh['indices']]
        flat = [v for tri in mesh['triangles'] for v in tri]
        if indexed != flat:
            errors.append('Exported triangles disagree with indexed vertex buffer')
    if nav is not None:
        if nav.get('source_hash') != mesh.get('source_hash'):
            errors.append('Navigation and mesh source_hash differ')
        if nav.get('geometry_hash') != mesh.get('canonical_geometry_hash'):
            errors.append('Navigation and actual mesh geometry_hash differ')
        if set(nav['supported']) != set(domain) or set(nav['allowed']) != set(domain):
            errors.append('Navigation cell domain differs from actual mesh')
        for key, admitted in nav['supported'].items():
            actual = anchors.get(key, {})
            if admitted and (not actual.get('dry') or not actual.get('continuous')):
                errors.append(f'Unsupported/wet/ambiguous admitted anchor {key}')
            if admitted and abs(float(nav['support_heights'][key]) - actual['height_min']) > HEIGHT_EPS:
                errors.append(f'Actor support height differs from actual triangle at {key}')
        for key, neighbors in nav['allowed'].items():
            if len(neighbors) != len(set(neighbors)):
                errors.append(f'Duplicate neighbor at {key}')
            for other in neighbors:
                pair = tuple(sorted((key, other)))
                actual = edges.get(pair)
                if actual is None or not actual['dry']:
                    errors.append(f'Admitted edge is uncovered, nonadjacent or wet: {key} -> {other}')
                if not nav['supported'].get(key) or not nav['supported'].get(other):
                    errors.append(f'Admitted edge has unsupported endpoint: {key} -> {other}')
                if key not in nav['allowed'].get(other, []):
                    errors.append(f'Asymmetric edge: {key} -> {other}')
        for (a, b), result in edges.items():
            if result['dry'] and b not in nav['allowed'].get(a, []):
                conservative.append([a, b])
        spawn_value = nav.get('spawn')
        spawn = ','.join(map(str, spawn_value)) if isinstance(spawn_value, list) else spawn_value
        if spawn not in domain or not nav['supported'].get(spawn) or not nav['allowed'].get(spawn):
            errors.append('Spawn lacks dry connected support')
        reachable, queue = set(), [spawn]
        while queue:
            key = queue.pop()
            if key in reachable:
                continue
            reachable.add(key)
            queue.extend(n for n in nav['allowed'].get(key, []) if n not in reachable)
    else:
        reachable = set()
    result = {'ok': not errors, 'source_hash': mesh.get('source_hash'), 'geometry_hash': mesh.get('canonical_geometry_hash'),
              'triangles': len(mesh['triangles']), 'cells': len(domain), 'dry_anchors': sum(x['dry'] for x in anchors.values()),
              'adjacent_undirected_edges': len(edges), 'dry_edges': sum(x['dry'] for x in edges.values()),
              'wet_or_uncovered_edges': sum(not x['dry'] for x in edges.values()),
              'navigation_compared': nav is not None, 'spawn_reachable_cells': len(reachable),
              'dry_edges_omitted_by_navigation': len(conservative), 'conservative_edge_examples': conservative[:10],
              'errors': errors, 'scope': 'actual emitted triangle support and center-segment water clearance; not actor footprint, slope permission or all-seed proof'}
    return result


def self_test():
    def quad(x0, x1, y0=1, y1=1):
        a, b, c, d = [x0, y0, -1], [x1, y1, -1], [x0, y0, 1], [x1, y1, 1]
        return [[a, b, c], [b, d, c]]
    cases = []
    def check(label, value):
        cases.append({'name': label, 'ok': bool(value)})
    flat = MeshOracle(quad(0, 1))
    check('flat fully covered dry', flat.segment((0, 0), (1, 0))['dry'])
    check('flat center height', abs(flat.anchor((.5, 0))['height_min'] - 1) < 1e-12)
    hole = MeshOracle(quad(0, .4) * 4 + quad(.6, 1) * 4)
    check('overlap sums cannot conceal central gap', not hole.segment((0, 0), (1, 0))['covered'])
    check('outside mesh not supported', not flat.anchor((2, 0))['covered'])
    check('crossing wet triangle rejected', not MeshOracle(quad(0, 1, 1, -1)).segment((0, 0), (1, 0))['dry'])
    check('zero-height endpoint rejected', not MeshOracle(quad(0, 1, 1, 0)).segment((0, 0), (1, 0))['dry'])
    check('exact diagonal shared boundary covered', flat.segment((0, 1), (1, -1))['dry'])
    check('point at clearance rejected', not MeshOracle(quad(0, 1, .0001, .0001)).anchor((.5, 0))['dry'])
    return {'ok': all(row['ok'] for row in cases), 'passed': sum(row['ok'] for row in cases), 'total': len(cases), 'cases': cases}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mesh', type=Path)
    parser.add_argument('--navigation', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    result = {'oracle_self_test': self_test()}
    if args.mesh:
        mesh = json.loads(args.mesh.read_text())
        nav = json.loads(args.navigation.read_text()) if args.navigation else None
        result['audit'] = audit(mesh, nav)
        result['inputs'] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.mesh, args.navigation) if p}
    result['ok'] = result['oracle_self_test']['ok'] and result.get('audit', {'ok': True})['ok']
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.out:
        args.out.write_text(text)
    print(text)
    raise SystemExit(0 if result['ok'] else 1)

if __name__ == '__main__':
    main()
