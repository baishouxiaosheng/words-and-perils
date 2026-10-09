# Actual player-details verification, unadopted

Clock: **165** actual checks; location: **234**; combined: **305**. Each bound source passed a new independent guarded parse and suite; successful runs contain no ERROR/WARNING. GUI test script parse also passed.

The existing v3 guard rejected the graphical attempt with `ArgumentException: godot_requires_explicit_headless`, engine PID **0**. **Screenshots and video NOT_RUN; delivery incomplete.** The guard was preserved and the rejected graphical mode was not rerouted.

Portable packages passed **61/57 available static and preparation checks**, with two symlink negative fixtures per package explicitly **NOT_RUN** because of the previously observed WinError1314; no symlink creation or privilege change. Their original assertions remain present for supported hosts. Preparation also rejects Windows reparse components before creating output.

All failed manifest/parse-wrapper attempts and transient TLS gates are preserved. The corrected parser uses typed Script objects after dual-API isolation without instantiating test bodies. Total real engine starts **8**: one failed wrapper parse, six successful component parse/suite runs, one successful GUI-wrapper parse. A graphical guard attempt did not start an engine. Formal v30 and the nine prior terminal results are unchanged.

Artifacts: [a52a7e5e12228c0cb47a0254f452dd232c380562](https://github.com/baishouxiaosheng/words-and-perils/commit/a52a7e5e12228c0cb47a0254f452dd232c380562). See ARTIFACTS.json, TEST_SUMMARY.json, SOURCE_HASHES.json and complete per-run guard/stdout/stderr evidence.

Next: validated guarded graphical support is absent; preserve the v3 guard and report that blocker. Do not rerun terminal IDs or call headless/static success full Main/UI acceptance.
