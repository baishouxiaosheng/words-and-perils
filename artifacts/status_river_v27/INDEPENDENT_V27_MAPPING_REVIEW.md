# Independent v27 adoption mapping check

2026-10-05 23:34 UTC. Result: **accept the exact v27 source mapping and completed smoke; no code or smoke blocker found.** Canonical-pointer update remains the separately authorized owner action.

## Verified source identity

- Final candidate freeze: `artifacts/FINAL_SOURCE_FREEZE.json`, SHA256 `c27cb5d203d1a350a46a5f6de64a4a4bf30a09fcb2073166f8b94c30977ae716`.
- All 76 listed files independently rehashed in both candidate overlay and actual `wordsandperils_v27`: 152/152 match the final freeze. All 50 production application pins match. These are 50 production changes, 25 acceptance-test files, and one unchanged legacy Basic pin, not 76 new production files.
- `adoption_v27/CLOSED_COPY_MAPPING.json`, SHA256 `6aaf60dca634b8ab1abb5c69c48f41fe3e4b8001fa34c537358a6ac91d0b2f95`: 4637 unique base records, exactly 310001936 B, correct v26/v27 roots, expected 75 applied paths (50 production + 25 tests), and matching final freeze, production manifest and prior independent review hashes.
- Reviewed the preparation script: it streams each source once, hashes destination, asserts unchanged source metadata and distinct destination inode/nlink1, applies the 75 frozen files, and checks unchanged legacy Basic before renaming the independent tree.
- Independently stat-checked every one of the 4637 mapping source/destination pairs: recorded devices/inodes match; source metadata is unchanged; unaffected destination size/mtime match; all pairs are distinct inodes. Replaced destination contents are covered by the 76 small-file hashes above. All files currently in the target tree are ordinary nlink1 files and no target symlinks were found.
- No second read of the 310 MB base/assets was performed. Full-copy byte identity is supported by the recorded preparation checks; this review independently confirms their source map, current metadata, code pins, and actual-tree smoke.

## Actual v27 smoke

Logs and guards: `adoption_v27/native_retry/`.

| Case | Assertions | PID | Seconds | Exit |
|---|---:|---:|---:|---:|
| main_poison | 87/87 | 111018 | 25.7915 | 0 |
| main_poison_reopen | 73/73 | 111109 | 22.1479 | 0 |
| equipment | 44/44 | 111155 | 22.9296 | 0 |

All three logs have zero script errors, errors, or warnings. Guards retain 8589934592 B cgroup limit, 8053063680 B stop threshold, and 536870912 B reserve. Maximum sampled cgroup across these three runs: 7106834432 B, below stop. Final current: 5987422208 B. Actual adopted runner guard SHA256 `e0a5e40a27d643a2eef35ac1d043924e5c3c965cb7db486deeb0ab12051e9ff8` equals original v26.

`adoption_v27/NATIVE_CLOSURE.json` records 876 runtime files / 42484395 B checked exact by the owner. `writable_outputs_private:false` reflects verification against the independent editable project rather than the earlier private linked-runtime mode; it does not mean source bytes are linked. The smoke runner's XDG output paths are explicitly inside the accepted Gate B scratch subtree.

The original `adoption_v27/native/main_poison.log` failure is preserved: 0/1, exit1, exact message `user-data output is confined to the explicit Gate B scratch subtree`. The successful retry fixes the runner output destination; final production and guard byte checks show no production/guard change. Do not count the first attempt as a pass.

## Final-delivery bookkeeping boundary

The initial CLOSED_COPY_MAPPING records **base copy plus applied-path instructions**, not a final whole-tree byte manifest after smoke and documentation. Current expected base+overlay union contains 4696 files. At this review there are 4699 target files, with exactly three additional nonproduction files:

- `docs/status_river_v27.md`: 4057 B, SHA256 `6dbce0dde56d6a1e85ff37952d257b50ec79f50700b70cd716706f356cc6e74d`
- `artifacts/public_witness.json`: 70952 B, SHA256 `847462d0375289ed0a0bf7e6c4bd161303a611759a1d52dccf61ace1c37d31f2`, matching the frozen existing real-public witness
- `artifacts/generated_v3_river_entry/main_roundtrip_report.json`: 3610 B, SHA256 `b1a9bc70098f6e743e1c331a7e22917fe8ba9dfc3602a56f064f4ce449c5f14d`

No expected path is missing. The delivery delta/receipt should explicitly include these additions, and separately any later documentation changes. This bookkeeping requirement does not alter the accepted 50 production source pins. The full candidate limitations in `FINAL_INDEPENDENT_ACCEPTANCE.md` remain: no new live-model, OS-input, long-run GPU/resource or comprehensive-art certification.

Reviewer performed only read/stat/hash checks and wrote this report. No engine was launched, no large runtime asset was reread, and neither production nor canonical was modified by this review.
