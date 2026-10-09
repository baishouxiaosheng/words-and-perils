#!/usr/bin/env python3
"""Read-only GLB bytes/hierarchy bounds checks. Does not invoke Godot."""
from __future__ import annotations
import hashlib
import json
import math
from pathlib import Path
import re
import struct

GAME = Path(__file__).resolve().parents[2]
CATALOG = GAME / 'core/generated_v3_placement/asset_catalog.json'
EPS = 2e-5
IDENTITY = tuple(float(i == j) for i in range(4) for j in range(4))


def multiply(a, b):
    return tuple(sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4)) for r in range(4) for c in range(4))


def node_transform(node):
    if 'matrix' in node:
        raw = node['matrix']
        return tuple(raw[c * 4 + r] for r in range(4) for c in range(4))
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    sx, sy, sz = node.get('scale', [1, 1, 1])
    tx, ty, tz = node.get('translation', [0, 0, 0])
    return ((1 - 2*y*y - 2*z*z)*sx, (2*x*y - 2*z*w)*sy, (2*x*z + 2*y*w)*sz, tx,
            (2*x*y + 2*z*w)*sx, (1 - 2*x*x - 2*z*z)*sy, (2*y*z - 2*x*w)*sz, ty,
            (2*x*z - 2*y*w)*sx, (2*y*z + 2*x*w)*sy, (1 - 2*x*x - 2*y*y)*sz, tz,
            0, 0, 0, 1)


def glb_geometry(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from('<III', data)
    assert (magic, version, length) == (0x46546c67, 2, len(data)), path
    offset = 12
    doc = None
    binary = None
    while offset < len(data):
        size, kind = struct.unpack_from('<II', data, offset)
        chunk = data[offset + 8:offset + 8 + size]
        if kind == 0x4e4f534a:
            doc = json.loads(chunk)
        elif kind == 0x004e4942:
            binary = chunk
        offset += size + 8
    assert doc and binary is not None, path

    def accessor(index):
        entry = doc['accessors'][index]
        assert 'sparse' not in entry
        view = doc['bufferViews'][entry['bufferView']]
        assert view.get('buffer', 0) == 0
        count = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[entry['type']]
        fmt = '<' + {5121: 'B', 5123: 'H', 5125: 'I', 5126: 'f'}[entry['componentType']] * count
        stride = view.get('byteStride', struct.calcsize(fmt))
        start = view.get('byteOffset', 0) + entry.get('byteOffset', 0)
        return [struct.unpack_from(fmt, binary, start + i * stride) for i in range(entry['count'])]

    points = []
    triangles = 0
    meshes = 0

    def visit(index, parent):
        nonlocal triangles, meshes
        node = doc['nodes'][index]
        transform = multiply(parent, node_transform(node))
        if 'mesh' in node:
            meshes += 1
            for primitive in doc['meshes'][node['mesh']]['primitives']:
                assert primitive.get('mode', 4) == 4
                vertices = accessor(primitive['attributes']['POSITION'])
                indices = [x[0] for x in accessor(primitive['indices'])] if 'indices' in primitive else list(range(len(vertices)))
                assert len(indices) % 3 == 0
                triangles += len(indices) // 3
                for i in indices:
                    v = (*vertices[i], 1)
                    point = tuple(sum(transform[r * 4 + k] * v[k] for k in range(4)) for r in range(3))
                    assert all(math.isfinite(x) for x in point)
                    points.append(point)
        for child in node.get('children', []):
            visit(child, transform)

    for node in doc['scenes'][doc.get('scene', 0)]['nodes']:
        visit(node, IDENTITY)
    assert points
    return {'min': [min(p[i] for p in points) for i in range(3)],
            'max': [max(p[i] for p in points) for i in range(3)], 'triangles': triangles, 'mesh_nodes': meshes}


def main():
    raw = CATALOG.read_bytes()
    sha = hashlib.sha256(raw).hexdigest()
    pinned = re.search(r'const SHA="([0-9a-f]{64})"', CATALOG.with_suffix('.gd').read_text()).group(1)
    assert sha == pinned, 'Catalog hash is not pinned identity'
    catalog = json.loads(raw)
    result = {'ok': True, 'native_engine_run': False, 'asset_catalog_hash': sha, 'assets': []}
    for name, row in catalog['assets'].items():
        versions = []
        for file_key, hash_key, lod_key in [('glb', 'sha256', 'lod0'), ('lod1_glb', 'lod1_sha256', 'lod1')]:
            path = GAME / catalog['asset_root'].removeprefix('res://') / row[file_key]
            assert hashlib.sha256(path.read_bytes()).hexdigest() == row[hash_key], name
            measured = glb_geometry(path)
            assert measured['triangles'] == row[lod_key]['triangles'], name
            versions.append(measured)
        full, low = versions
        for i in range(3):
            assert abs(full['min'][i] - row['aabb_min_xyz'][i]) < EPS, (name, full)
            assert abs(full['max'][i] - row['aabb_max_xyz'][i]) < EPS, (name, full)
            assert low['min'][i] >= full['min'][i] - EPS, (name, low)
            assert low['max'][i] <= full['max'][i] + EPS, (name, low)
        result['assets'].append({'id': name, 'full': full, 'lod1': low, 'lod_contained': True})
    for prefix in ['material', 'material_shader']:
        path = GAME / catalog[prefix + '_path'].removeprefix('res://')
        assert hashlib.sha256(path.read_bytes()).hexdigest() == catalog[prefix + '_sha256']
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
