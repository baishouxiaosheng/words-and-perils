#!/usr/bin/env python3
"""Numeric evidence from actual GPU screenshots, never resynthesize the images."""
from pathlib import Path
import hashlib,json,sys
import numpy as np
from PIL import Image
run=Path(sys.argv[1]).resolve()
def im(name):return np.array(Image.open(run/(name+'.png')))[:,:,:3].astype(np.int16)
def erode(mask):
    return np.logical_and.reduce([np.roll(np.roll(mask,y,0),x,1) for y in [-1,0,1] for x in [-1,0,1]])
b,n,u,m=map(im,['B_clipped','B_no_cast','B_uncut','B_masks_form_cast_max'])
overlap=erode((m[:,:,0]>=254)&(m[:,:,1]>=254))
delta=np.abs(b-n).max(2)
assert int(overlap.sum())>25,'No actual overlapping shadow region'
assert int(delta[overlap].max())==0,'Form/cast overlap darkens the existing dark endpoint'
restore_exact=bool(np.array_equal(im('A_tabs'),im('A_restored')))
assert restore_exact,'A did not restore exactly'
y,x=np.indices(delta.shape)
# Fixed diagnostic rectangle enclosing the near ridge skirt, outside the tree grove.
# Green-only pixels are selected from the no-cast control. Counts measure change,
# not a claim that every changed pixel is an unwanted shadow.
roi=(x>=200)&(x<1100)&(y>=290)&(y<780)&(n[:,:,1]>n[:,:,0]*1.05)&(n[:,:,1]>n[:,:,2]*1.5)
du=np.abs(u-n).max(2)
guard=[json.loads(s) for s in (run/'guard.jsonl').read_text().splitlines()]
report=json.loads((run/'report.json').read_text())
gap=report['proxy']['max_sampled_contact_edge_gap_world']
diameter=2*np.sqrt((7.3/2)**2+(7.3*1280/960/2)**2+((22-.2)/2)**2)
result={
 'scope':'actual 1280x960 ridge fixture; not full Main or target hardware acceptance',
 'A_restore_pixel_exact':restore_exact,
 'overlap_interior_pixels':int(overlap.sum()),
 'overlap_rgb_max_difference_from_form_only':int(delta[overlap].max()),
 'near_ridge_green_roi_pixels':int(roi.sum()),
 'uncut_vs_no_cast_roi_pixels_over_4_levels':int((roi&(du>4)).sum()),
 'clipped_vs_no_cast_roi_pixels_over_4_levels':int((roi&(delta>4)).sum()),
 'roi_pixels_changed_uncut_then_restored_by_clip':int((roi&(du>4)&(delta<=1)).sum()),
 'sampled_contact_gap_world':gap,
 'sampled_gap_projected_vertical_pixels':gap*960/7.3*.730121,
 'estimated_far_split_sphere_diameter_world':float(diameter),
 'estimated_bias_reference_texel_world':float(diameter/2048),
 'sampled_gap_as_bias_reference_texels':float(gap/(diameter/2048)),
 'atlas_tile_pixels':[2048,1024],
 'max_owned_engine_rss_mib':max(s.get('VmRSS_kib',0) for s in guard)/1024,
 'cgroup_peak_mib':max(s.get('cgroup_current',0) for s in guard)/1024**2,
 'cgroup_peak_additional_mib':(max(s.get('cgroup_current',0) for s in guard)-guard[0]['cgroup_current'])/1024**2,
 'engine_elapsed_s':guard[-1]['elapsed_s'],
 'png_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(run.glob('*.png'))},
 'remaining_visual_issue':'Thin self-shadow stripes remain on some light-facing mountain facets. This run does not establish complete visual acceptance.',
}
(run/'pixel_analysis.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
