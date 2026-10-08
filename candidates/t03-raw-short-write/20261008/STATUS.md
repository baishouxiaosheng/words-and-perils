# T03 raw temporary-write result check candidate

Status: isolated unrun source candidate. Not adopted, composed with other candidates, uploaded, or published by this task. Godot parsing 0; Godot runtime execution 0. The frozen restored project, prior natural-coast save guard candidate, existing player saves, README, and save/load signatures were not changed.

## Confirmed call chain and defect

The frozen `core/ai_gm_rebuilt/engine.gd:415` raw `save_file(path)` opened `path + ".tmp"`, discarded the return from `store_string`, flushed and closed, then attempted the destination rename. A reported short-write failure could therefore still reach rename.

The frozen natural-coast Engine extends that core and inherits its raw writer. The separately saved natural-coast identity-guard candidate overrides raw `save_file` but finishes with `super.save_file(path)`, so the same underlying I/O issue remains there. The ordinary `view/ai_gm_playtest/adapter.gd:94` delegates directly to its Engine; non-status playable-build saves reach that route. This narrow patch changes the core raw writer only. Other envelope writers, including natural-coast adapter and status-gameplay save implementations, do not become fixed by changing this inherited raw method.

## Minimal change

Exactly one production file changes. One old semicolon-combined statement becomes five statements:

1. Retain the bool returned by `store_string(C.bytes(save_data()))`.
2. Flush as before.
3. Retain the file-reported error before close.
4. Close as before.
5. Return the existing `SAVE_FAILED` error category if either signal indicates failure, before the explicit destination rename.

The readiness check, temporary path and open mode, canonical payload, raw save format, rename operation, pre-existing rename-failure text, successful return, every load/admission function, every non-save function and existing method signature are byte-identical. No cleanup deletion or new production dependency was introduced. Failed opens preserve the temporary sentinel; a failed write may have already truncated/partially written the temporary file, which is retained for inspection. This patch does not promise to preserve an existing temporary file after a successful open.

Base Engine: 50,887 bytes, SHA-256 `3d41f2fc4e52459d5df01732fbacc9e849f0e4a9260094220426001ef236002d`.

Candidate Engine: 51,047 bytes, SHA-256 `cb707722b1d28534615257cb9873d1c66ce9924ac2ee5ebdc2d1d2a46b09fdc3`.

Exact candidate method SHA-256: `a67af61429e9d9caef0b16b182682319389eb52600a1de5c85f74564051d811c`.

## Actual verification

Final 23 Python source/byte/order consistency checks passed. A one-file disposable copy accepted the patch with `--fuzz=0`, and its resulting bytes exactly matched the overlay. These are static checks and patch application only; they do not parse or run GDScript. `STATIC_CHECKS.json` and `PATCH_APPLICATION_CHECK.json` contain the evidence. No current full-project/168-file rehash was performed; the earlier 168-input snapshot supplies provenance for the core base hash, and the small declared input subset was rechecked.

The initial Python checker incorrectly counted the shared `start_case` call inside the probe helper as an additional runtime case. Its single false case-count check was corrected; that initial checker result is retained in `STATIC_CHECKS_initial_case_counter_failed.json`. This was a static verifier bookkeeping error, not a Godot or product failure. A first patch command did not start because the disposable working directory had not yet been created; after creating it, the only actual patch application passed at zero fuzz.

An independent read-only review found no blocking production patch issue or obvious GDScript syntax hazard. It identified decoded-String versus byte-array wording in native test assertions. Those three assertions were corrected to compare `get_file_as_bytes` with expected UTF-8 buffers before final static checks. The final review is recorded separately; it is not a parser result.

## Ten prepared, never-executed runtime cases

The test suite pins the exact candidate Engine source and extracted method hashes. It extracts that production method and substitutes only the FileAccess/DirAccess backend identifiers into a test-only in-memory backend. The entire method's decisions, error categories, payload call and operation ordering remain source-bound. This introduces no production injection seam.

Seven in-memory cases: false store result with OK error; false result with reported write error; true result with reported error; temporary open failure; rename failure; successful write; unready Engine with no I/O. The synthetic backend contains non-empty pending and receipt fields and uses a character-prefix truncation to signal failure. This verifies decision logic if run; it is not actual operating-system byte short-write evidence.

Three native cases: ordinary save and strict reload; repeated unassessed-pending save; temporary open failure caused by a test-only directory while preserving destination bytes and full live payload. Those native fixtures do not contain non-empty committed receipts. All native artifacts are beneath a unique isolated test `user://` directory. No user save is read, removed, or reused.

All ten cases are prepared only, not passed. The test suite itself has never been Godot-parsed or executed.

## API basis and remaining risk

The restored project declares Godot 4.6. Official 4.6 documentation and source confirm the bool return and short-write comparison behind `store_string`; `OFFICIAL_API_NOTES.json` links the sources. The patch targets that API, with no claim of compatibility with earlier void-returning versions.

Godot's Unix and Windows `flush()` implementations ignore the underlying `fflush` return and do not refresh `last_error`. A later buffered-write failure can consequently escape this method's reported-error check; close/durability failures are also not resolved. No claims of OS replacement atomicity, fsync/directory sync, crash consistency, or power-loss durability are made.

The deterministic shared `.tmp`, concurrent writers, TOCTOU after identity checks, aliases/symlinks and other modes' arbitrary-path/envelope writers remain outside this change. Only this invocation's explicit rename is skipped on observed store/error failures; another process can still alter files. T03 remains open.

The core file is already in natural-coast AuthorityInputs.FILES. Its new hash advances that runtime identity even though signatures, the authority-input list and strict load validation are unchanged. This candidate does not migrate old saves or relax public/native distribution boundaries. The earlier natural-coast identity-guard candidate is separate and unchanged; its 23 static checks and 13 unexecuted runtime cases do not validate a combined candidate.

## Next gate

Required native memory.max and memory.current interfaces remain absent, so the memory guard was not weakened and no Godot was started. Once the supported native guarded route becomes available, verify these bindings, apply only to a fresh disposable exact project with isolated user://, and parse/run the ten-case suite. Also run the existing affected core/natural-coast suites under independently derived candidate identity pins. Keep the prior identity-guard candidate and the frozen restore separate; any composition needs a new manifest and fresh tests.

Future actual short-write/late-flush fault testing needs a controlled native filesystem/backend, scoped to disposable artifacts. Do not use live saves or infer such coverage from the in-memory fault backend. Parent publication under the existing project permission is a candidate checkpoint only, never formal adoption.
