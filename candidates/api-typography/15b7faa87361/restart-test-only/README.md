# Real Main save → process exit → new Main Continue

Test-only attachment. It does not change the five accepted production files, public authority/Save protection, restore entrypoint, or existing fixtures. The script has not been executed in the cloud. A clean strict result from both actual laptop processes is required.

One script, two separate invocations:
`tests/dual_api_settings/test_main_restart.gd`

## Isolation and sequence

Use a fresh test user-data directory, separate from the prior player's data and protected fixture trees. Keep the full restored public project and all five production source pins unchanged. The writer refuses to overwrite an existing Coast save, narration sidecar, report, or same-nonce receipt.

For both invocations, set `FOGBANK_API_TEST_USER_DIR` to the exact `OS.get_user_data_dir()` configured for the isolated project, and set `FOGBANK_API_RESTART_NONCE` to the same new 16–80 character ASCII letters/digits/underscore/hyphen identifier. Do not pass Godot user arguments after `--`. Set `FOGBANK_API_RESTART_STAGE=write` for the first process, then `read` for the second.

Run the selected official Godot executable with the existing background process/resource guard, `--path <isolated-project> --script res://tests/dual_api_settings/test_main_restart.gd`, and the same approved display mode as the previous Main acceptance. Record the actual PID, command, startup time, complete stdout/stderr and exit for each process. Do not launch the reader until the writer has fully exited with zero status, its result has `ok:true`, and the strict full logs contain no script errors or shutdown warnings.

The writer saves the actual default Main Coast slot and sidecar, then writes:
- `user://api_restart_receipt_<nonce>.json`
- `user://api_restart_write_<nonce>.json`

Record the writer report SHA and independently hash the receipt. Pass that exact receipt SHA as `FOGBANK_API_RESTART_RECEIPT_SHA256` when launching the fresh reader process. The reader verifies the nonce, different process PID, identical test source and production pins, and exact save/sidecar hashes. It writes `user://api_restart_read_<nonce>.json`. It does not rewrite the save files. Preserve these small reports and files as isolated test evidence; do not use a previous report as a new run.

## What is checked

Both processes instantiate actual `main.tscn`, require the real public 1801-cell Coast world/scene, default release rule/adapter, real source board and validated public Bundle identity. No private native digest or external authority fixture is substituted.

Writer opens the actual two-role API modal, applies only explicit dummy keys with a mock transport, performs one ordinary unseeded observation through Main's primary action and commits a bound narration. Main's real save method writes the disk save and prose sidecar. The receipt records hashes of the complete authoritative engine/world/RNG/action/history/prose, plus actual world, turn, position, health, stamina and inventory identity. Both dummy keys are rejected from save/sidecar/receipt bytes.

Reader starts a new actual Main process, proves roles are unconfigured and offline before load, calls Main's real load/Continue method, then compares the complete state, RNG, resources, position, action, history and prose to the writer. It also requires exactly one displayed prose entry, unchanged disk files and zero mock sends after Continue. The reader cannot recover either session-only key.

The test proves the exercised API route uses the injected in-memory transport; it is not an OS traffic capture or a live-provider test. A result file does not certify process exit: the runner must keep its actual strict exit/log evidence. Do not suppress warnings or alter assertions to obtain a pass. This is a finite restart check, not a broad combat/status/experimental-world matrix.

## Dependencies

Complete restored public v28 plus the fixed five-file API/typography candidate, the existing `tests/ai_gm_http/mock_transport.gd`, `core/ai_gm_rebuilt/canonical.gd`, and `view/playable_build/world_bundle.gd`. All world/catalog/closure data come from that validated public project. Only this new test path and its manifest/instructions are supplied; existing fixture and production paths remain untouched.
