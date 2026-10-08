# T03 natural-coast save guard candidate

Status: independent source-only Git checkpoint, not adopted. No Godot parsing or Engine execution was performed. During source preparation, no player save, frozen candidate, backup, Git or Library object was changed. This checkpoint stores only the separate candidate sources and text evidence.

## Confirmed defect in the exact restored base

The published natural-coast UI view already compared full saved identity. Its protection did not cover direct adapter calls or independent natural-coast adapters. The adapter's existing write guard accepted schema/profile plus generated source content_hash. Identical terrain content can exist with different authority code hashes, inventory_profile_hash, runtime_hash and world_id between public/native distributions. The unchanged source admission/load code rejects those different signatures, but the old direct write guard could replace such a save first.

The natural CoastEngine inherited core Engine.save_file without an existing-destination identity check. Calling adapter.engine.save_file directly could replace either a foreign raw save or a natural-coast envelope. A raw payload would also destroy the envelope format even when the runtime identity was the same.

## Narrow changed behavior

- Natural adapter writes require exact envelope fields and safe typed JSON, exact source payload, content hash, renderer profile, geometry hash, full source/runtime identity and matching Engine schema/rule/resolver/policy/world/authority identities.
- The natural Engine records its original world/full authority identity at construction, using exactly the inherited constructor signature and one inherited initialization. Both current state and the existing destination must match that fixed identity; an inherited raw load cannot redefine write authority. Loading itself remains unchanged.
- The direct natural CoastEngine raw writer rejects an unreadable, oversized, malformed or foreign existing raw save. It also refuses every adapter envelope, including its own identity, to preserve the stored format.
- Both guards inspect existing files only. Every refusal returns before the adapter opens .tmp or the direct API delegates to its inherited temp-write/rename function. Existing destination and temporary-file contents are untouched on those refusal paths.
- Missing destinations and recognized same-distribution same-runtime saves remain allowed. The adapter's save encoding/temp-write/rename implementation, all load/admission functions, existing Engine methods and request signatures remain byte-identical.

Two production files changed. The third overlay file only adds thirteen focused cases to the existing natural-coast adapter suite. MANIFEST.json binds every changed file to exact base and candidate SHA-256. BASE_AUTHORITY_INPUTS.json binds all 168 existing authority files.

## Identity and safety boundary

Both changed production files already belong to AuthorityInputs.FILES. Their new hashes advance the natural-coast profile/runtime/world identity. The authority-input list, signature calculation and exact load validation were not altered. Existing old-version or other-distribution saves remain protected; this candidate offers no migration, cross-distribution interoperability or old-save compatibility.

The current UI guard remains unchanged. Generic core Engine and other modes' explicit arbitrary-path writers are outside this narrow change and remain unclosed residual scope. T03 is not complete.

## Exact compatibility scope

The frozen fields are only world_id and the generated_world identity copied from Source's immutable next_identity. Actor health, stamina, item custody/quantities, statuses, flags, turn, state_version and mutable world-state dictionaries are not captured or compared by this new identity guard. The current natural-coast Source contract already treats its source terrain/geometry/navigation identity as fixed; no new mutable-terrain policy was introduced.

Same-distribution saves with the same exact generated/source/runtime/world identity remain writable under this candidate. Do not broaden this to all same-distribution saves or older source revisions. The existing blank Adapter.load_data path still admits a valid source, creates a new Engine for that source and validates its save, so separately saved legal seeds/recipes can still be opened through a new adapter. This is a source-level compatibility conclusion pending runtime confirmation.

The inherited direct raw Engine.load_data can still accept a different otherwise-valid world/seed. If it does so on an already constructed natural Engine, subsequent save_file now refuses because that instance's original source identity differs. Rebuild the adapter/Engine from that source before saving; do not reinterpret or migrate the file. This is an explicit narrowing of the direct raw API's previous behavior, not a claim that every old same-distribution raw-load/write sequence remains supported.

## Write implementation and concurrency limits

The original adapter checks readiness/destination, validates state, encodes, writes a deterministic path+.tmp, flushes, checks FileAccess.get_error, closes and calls DirAccess.rename_absolute. The raw core Engine performs temporary write/flush/close/rename without checking get_error. The new direct override delegates to that unchanged raw function. An incomplete raw temporary write can therefore still reach rename; this candidate does not repair that separate I/O defect.

These are temporary-file/rename implementations. No runtime evidence here establishes platform/filesystem replacement atomicity, crash durability, directory syncing or a complete atomic-save guarantee. This report does not claim those properties were verified or newly preserved.

Neither route revalidates destination identity immediately before rename, acquires a lock or owns a unique/exclusive temporary file. Another process can change the destination after the identity check, and concurrent writers can collide on the shared path+.tmp. The candidate prevents the confirmed single-invocation foreign-identity overwrite and returns before any write on its guard-refusal paths; it does not solve those cross-process races. Do not claim all data-loss risks or T03 are closed.

Other known unmodified arbitrary-path save routes include core/ai_gm_rebuilt/engine.gd:415, reached from view/ai_gm_playtest/adapter.gd:94 and non-status playable_build/adapter.gd:262; view/generated_adventure/adapter.gd:87, including seeded_adapter.gd:53; and core/game_state.gd:243. Their existing-file destination protection is outside this narrow candidate.

## Actual verification

Twenty-three source/static checks passed. They include exact base/overlay/168-file bindings, unchanged save/load/admission and existing Engine bodies, pre-write ordering, a synthetic source-predicate counterexample for the old guard, and zero-fuzz patch application to a disposable three-file base with exact output matching. STATIC_CHECKS.json lists their individual labels.

A read-only independent source review found no blocking production-guard issue and no obvious GDScript type/syntax hazard. This does not substitute for Godot parsing.

Thirteen prepared runtime checks cover repeated same-runtime envelope/raw saves; a separate same-distribution adapter; equal-terrain foreign runtime identity; hidden mismatching Engine world identity; raw-versus-envelope format protection; malformed source/JSON; existing temporary sentinels; and byte-identical live state/RNG/pending/receipts after attempted writes. The thirteenth case checks that a direct raw foreign load either rejects unchanged or makes subsequent writing refuse against the constructor-bound identity. These checks have NOT run. Synthetic foreign fixtures are not evidence from an actual public/native distribution pair.

## Remaining test gate

The supported native environment currently lacks both required memory.max and memory.current interfaces. No fallback or guard relaxation was attempted and no unchanged Engine attempt was requested.

After those interfaces are restored, use the approved native guarded route with an exact disposable project and isolated user:// directory. Verify the overlay's base hashes first; preserve the old candidate separately. Run existing compile and adapter checks for both coastal_range and plateau_hinterland, then actual independently restored public/native identity-pair refusal checks with destination/tmp hashes and live-state comparison. Include pending/locked same-runtime writes, a controlled temporary-write failure and normal reload under the same candidate identity.

The existing full adapter suite temporarily edits traversal_policy.gd before restoring it. It must never run against the frozen/live project or the user's actual save directory. Its adoption-smoke expected_identities.json pins belong to the older identity: do not weaken those assertions or overwrite old adoption evidence to make this candidate pass. New candidate runtime identities require separately derived/verified pins.

This source-only Git checkpoint is separate from formal adoption and broader T03 completion. Neither adoption nor T03 completion has occurred.
