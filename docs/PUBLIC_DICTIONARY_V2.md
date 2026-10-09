# Public dictionary v2: bounded, lossless transport

This is the first proposed adopted wire encoding; earlier v1 experiments were independent candidates only. It changes no existing save schema, authoritative world, rule outcome, RNG, model context hash or public visibility decision. The existing public JSON cap stays 65,536 bytes; the complete Client HTTP-body cap stays 4 MiB.

## Representation

An exact one-field object `{"$p":N}` resolves to `public_dictionary.values[str(N)]`. `N` must be an exact finite integer in 0–127; JSON integer values parsed as doubles are accepted only when exactly integral. Booleans, strings, negatives, fractions and out-of-range values reject. Table keys must be canonical decimal strings (`"0"` through `"127"`): leading zeroes, signs, decimal/exponent notation, numeric dictionary keys and unused invalid keys reject.

The table is flat, finite and reference-free. Values come only from already-public facts, capability data, complete selected public memory or compact active-status data. Goal, attention focus and protocol identity fields remain literal. Literal marker-shaped source objects or a pre-existing dictionary root disable packing without altering the original object; JSON-looking text remains ordinary text.

Every pack is re-expanded and compared to the original canonical request before it can be returned. The transmitted expanded digest binds all original values. Candidates use actual UTF-8 costs; parent replacement is accounted for using actual emitted-reference counts. Retained values are deterministically assigned short numeric IDs by usage and canonical-text ties, then checked again for positive savings. Each further pass removes a candidate, bounded by 129 passes. Final transmitted bytes must be smaller than the original. No facts, history records, intent clauses or focus fields are trimmed by this encoding.

The Codec explains the version before model assessment. Existing JSON-pointer paths are unchanged after expansion. Only `fact_refs[].expected` may use these public references; each is expanded against the cached trusted table, located at the original public path, compared immediately to the actual value, then submitted to the normal engine validator. Bindings, parameters and free text do not acquire substitution privileges.

## Resource and privacy guards

Table size remains at most 128. Expansion is measured before allocating decoded trees: at most 262,144 bytes, 16,384 nodes, depth 64. Reply expectations additionally cannot expand beyond their actual cited value size or the cumulative 524,288-byte allowance. These are internal safety ceilings, not increased wire budgets. Hidden NPC sources are absent from the original public projection and cannot enter the table; aliases do not grant new fact-reference paths.

## Actual measured boundary

The current real Coast fixture first commits six ordinary observations, then normally applies player poison and flight. It retains eight actual receipts. The original memory policy (six records / 4,096 record bytes) returns five complete records using 3,636 bytes, marks truncation, and leaves 460 bytes, less than the smallest remaining complete record (644). That original selection policy is unchanged.

The final real request measurements are:
- Short intent: 63,771 public bytes, margin 1,765
- 100 Chinese characters / 300 UTF-8 bytes, multiple named objects and compound intent: 64,027 bytes, margin 1,509
- 300 Chinese characters / 900 UTF-8 bytes: 64,627 bytes, margin 909
- Largest wrapper in those accepted rows: 76,591 bytes, within the original 4 MiB cap

The ordinary compound samples only establish that their complete requests can be sent. They do not claim every named compound action has a resolver or that a model judged it correctly. 4,095–4,097-byte intentions still exceed the combined public budget in this context and safely reject; long-intention support remains deferred. No API/model call occurred.

Evidence: native dictionary/real-scope replay 140/140 (`dictionary_native/attempt4`, recorded native run); real full-history gate 457/457 (`full_v2_final_native/budget_full_history`, recorded native run). Production is frozen in `V2_FINAL_FREEZE.json`, SHA256 `19bde25d256dfe5b6705ec04315338442b85e4a59ef70c306067cc17748f5109`. The 300-character margin is a bounded current-context observation, not unlimited future capacity.
