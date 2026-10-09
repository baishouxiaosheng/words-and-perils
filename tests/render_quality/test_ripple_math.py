"""CPU checks of the shader's analytical stripe coverage, not a render test."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DUTY = 0.04886327

def smooth(a, b, v):
    t = max(0.0, min(1.0, (v - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)

def integral(cycle):
    return math.floor(cycle) * DUTY + max(0.0, min(DUTY, cycle % 1 - (0.5 - DUTY * 0.5)))

def original(cycle):
    return smooth(0.975, 1.0, math.sin((cycle - 0.25) * math.tau))

def filtered(cycle, footprint):
    footprint = max(footprint, 0.00001)
    coverage = max(0.0, min(1.0, (integral(cycle + footprint * 0.5) - integral(cycle - footprint * 0.5)) / footprint))
    blend = smooth(0.01, 0.04, footprint)
    resolved = original(cycle) * (1 - blend) + coverage * blend
    distant = smooth(0.5, 1.0, footprint)
    return resolved * (1 - distant) + DUTY * distant

def main():
    checks = []
    def check(value, label):
        checks.append({"passed": bool(value), "name": label})
        assert value, label

    points = [(i + 0.37) / 20000 for i in range(20000)]
    check(abs(sum(original(v) for v in points) / len(points) - DUTY) < 1e-7, "filtered duty matches original mean ripple brightness")
    for width in [0.00001, 0.002, 0.01, 0.02, 0.04, 0.1, 0.3, 0.5, 1, 2, 10]:
        values = [filtered(v - 20, width) for v in points]
        check(all(math.isfinite(v) and 0 <= v <= 1 for v in values), f"finite bounded coverage, footprint {width}")
        check(abs(sum(values) / len(values) - DUTY) < 1e-5, f"mean brightness conserved, footprint {width}")
        check(max(abs(filtered(v, width) - filtered(v - 20, width)) for v in points[::20]) < 1e-7, f"negative-coordinate periodicity, footprint {width}")
    check(all(abs(filtered(v, 0.005) - original(v)) < 1e-12 for v in points), "well-resolved ripples retain exact original shape")
    check(all(filtered(v, 1.0) == DUTY for v in points), "unresolved distant pattern converges to stable mean")
    shader = (ROOT / "view/integrated_ecology_world/tabs_style/water.gdshader").read_text()
    before = (ROOT / "artifacts/render_quality_20261003/water_before_quality.gdshader.txt").read_text()
    # Retain all original water/shore/depth/palette expressions outside ripple block.
    for line in before.splitlines():
        if line.startswith(" float stripe="):
            continue
        check(line in shader, "original water/shore expression retained: " + line[:100])
    check("fwidth(cycle)" in shader and "fwidthFine" not in shader, "uses Compatibility-supported derivative on continuous phase")
    report = {"scope": "CPU math and source invariants only; no renderer or GPU claim", "checks": checks, "failures": 0}
    out = ROOT / "artifacts/render_quality_20261003/ripple_math.json"
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"RIPPLE MATH PASS: {len(checks)} checks")

if __name__ == "__main__":
    main()
