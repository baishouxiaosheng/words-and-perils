#!/usr/bin/env python3
"""Quantify one candidate; never turn invariant success into visual acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('run', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
run = args.run.resolve()
samples = json.loads((root / 'tests/slope_probe_samples.json').read_text())
report = json.loads((run / 'report.json').read_text())
validation = json.loads((run / 'validation.json').read_text())

def read(name):
    a = np.array(Image.open(run / (name + '.png')).convert('RGB')).astype(np.int16)
    if a.shape != (960, 1280, 3):
        raise ValueError('Unexpected image shape: ' + name + ' ' + str(a.shape))
    return a

B = read('B_clipped'); C = read('C_slope_depth'); N = read('B_no_cast')
raw_B = read('B_raw_attenuation'); raw_C = read('C_raw_attenuation')
form_B = read('B_form_only'); form_C = read('C_form_only')
masks = read('C_masks_form_cast_max')

def at(a, key):
    points = np.array(samples[key]['pixels_xy'])
    return a[points[:, 1], points[:, 0]]

clear_B = np.max(np.abs(at(B, 'clear_probe') - at(N, 'clear_probe')), axis=1)
clear_C = np.max(np.abs(at(C, 'clear_probe') - at(N, 'clear_probe')), axis=1)
clear_active = clear_B > 4
neighbor_B = at(raw_B, 'real_neighbor_probe')[:, 0]
neighbor_C = at(raw_C, 'real_neighbor_probe')[:, 0]
neighbor_deep = neighbor_B <= 8

overlap = (masks[:, :, 0] == 255) & (masks[:, :, 1] >= 128)
# Exclude silhouette/antialias edges with a two-pixel all-neighbor interior.
for dy, dx in [(0, 1), (0, -1), (1, 0), (-1, 0), (0, 2), (0, -2), (2, 0), (-2, 0)]:
    overlap &= np.roll((masks[:, :, 0] == 255), (dy, dx), axis=(0, 1))
overlap_delta = np.max(np.abs(C - N), axis=2)[overlap]

result = {
    'status': 'MEASURED_CANDIDATE_NOT_AUTOMATIC_VISUAL_ACCEPTANCE',
    'run': str(run),
    'probe_reference_commit': samples['reference_commit'],
    'probe_scope': samples['scope'],
    'engine_validation': validation,
    'depth_identity_matches_default': report['depth_identity_matches_default'],
    'custom_shadow_depth_route_proven': report['custom_shadow_depth_route_proven'],
    'caster_toggle_reversible': report['caster_toggle_reversible'],
    'pixel_exact_A_restore': report['pixel_exact_A_restore'],
    'geometry_pose_camera_unchanged': report['geometry_pose_camera_unchanged'],
    'form_pixels_exact': bool(np.array_equal(form_B, form_C)),
    'clear_ray_facet_4680': {
        'reference_samples': int(len(clear_B)), 'current_baseline_delta_gt4': int(clear_active.sum()),
        'returned_to_no_cast_within1': int(((clear_C <= 1) & clear_active).sum()),
        'candidate_delta_gt4_on_baseline_affected': int(((clear_C > 4) & clear_active).sum()),
        'baseline_mean_max_rgb_delta': float(clear_B[clear_active].mean()) if clear_active.any() else None,
        'candidate_mean_max_rgb_delta': float(clear_C[clear_active].mean()) if clear_active.any() else None,
    },
    'true_neighbor_shadow_facet_2920': {
        'reference_samples': int(len(neighbor_B)),
        'baseline_deep_shadow_attenuation_le8': int(neighbor_deep.sum()),
        'retained_deep_shadow_attenuation_le8': int(((neighbor_C <= 8) & neighbor_deep).sum()),
        'retained_cast_attenuation_lt128': int(((neighbor_C < 128) & neighbor_deep).sum()),
        'candidate_mean_attenuation_on_deep_baseline': float(neighbor_C[neighbor_deep].mean()) if neighbor_deep.any() else None,
    },
    'union_overlap': {'interior_pixels': int(overlap.sum()),
                      'maximum_rgb_difference_from_form_only_shade': int(overlap_delta.max()) if len(overlap_delta) else None},
    'png_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(run.glob('*.png'))},
    'pending_visual_review': ['Shadow/contact-outline displacement budget',
                              'Whole visible candidate image including retained real shadow shape',
                              'No full Main/SouthWatch/water/city/far acceptance is implied'],
}
(run / 'slope_pixel_analysis.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
