# Manual committed-receipt narration display candidate

Status: minimal source candidate; not adopted. Static checks passed. Godot parsing, real Engine/UI regression, screenshot/video capture and gameplay acceptance were not run.

## Exact scope and base

- Repository: baishouxiaosheng/words-and-perils
- Formal public-v30 commit: e8ec5db0341f8b4a8aaa0a933e5968c33440c9da
- Restored Main input: candidates/actor-public-v29-compat/05ebbe56e88d/production/main.gd, 203707 bytes, SHA-256 05ebbe56e88d2ac7e774527419a60fbfabbb819dd1b52a14748728c38939072f.
- The repository root Main was not substituted for this restored input.
- Gameplay target: unified actor_actions_v2, real player → one enemy → player sequence. The default generated_v3_enemy branch, status-v1 acceptance, multiple enemies, maps, provider/key work and HUD-layout changes are outside this candidate.
- The actor-v2 authority profile remains 084f3c14412ea01fd0d5f4023463232979376e8938a5800325feffa93371cc6e. All 131 authority dependencies were checked against the formal restoration chain. This is a byte/source check, not runtime acceptance.

## Confirmed source defect

The restored Main's apply_playtest_reply(), lines 2199–2203, correctly imports optional narration for an already committed receipt, including historical receipts. Line 2202 calls append_journal("叙事记录", result.narration) without the third argument.

append_journal(), lines 1152–1160, defaults update_latest to true. It appends the history entry and then overwrites dialogue_speaker.text, latest_dialogue.text and latest_dialogue.tooltip_text. An accepted old receipt's first manual narration therefore takes the current dialogue away from a newer pending player action or a newer committed action.

The intended ownership boundary already exists on the provider-callback path. _on_runtime_narration(), lines 2297–2300, labels the entry with the committed receipt's turn and only promotes actor-mode prose when action_id == playtest.last_action and playtest.phase() == "idle". The manual-import path lacked that same boundary.

This is a current-display attribution defect. The reviewed code does not show an Engine fact mutation, extra turn, repeated RNG draw or duplicate receipt commit caused by this display line.

## Authority and adapter evidence

- view/actor_action_entry/view_adapter.gd:183–198 validates narration against its committed receipt binding and Engine request before record_narration(). Historical prose is deliberately accepted while a newer action is pending.
- view/actor_action_entry/view_adapter.gd:199–206 records the sidecar; only the latest receipt changes the facade narration field. The candidate leaves this behavior intact.
- view/runtime_ai/narration_log.gd:21–33 requires a real committed receipt and de-duplicates by receipt identity.
- view/actor_action_profile_v2/scheduler.gd:133–142 keeps duplicate commits with the real Engine's validator and preserves a newer active slot.
- core/ai_gm_rebuilt/engine.gd:361–409 validates and atomically publishes the actual staged transaction. No change to this code is proposed.
- view/actor_action_profile_v2/policy.gd:26–30 makes the one actor-aware phase transition through the frozen hooks. No change to action ordering or downed-actor checks is proposed.

## Minimal repair

Only apply_playtest_reply() changes: one deleted line, five added lines. After the existing successful-import and already_recorded checks:

1. Read the narration's action_id from the validated reply.
2. For actor mode, label history with the actual committed receipt's immutable turn.
3. Use the same promote_latest condition as _on_runtime_narration().
4. Append the history entry once, passing that condition as update_latest.

Non-actor manual narration retains its existing caption and promotion behavior. No new helper, Engine transaction, queue, retry, scheduling rule or layout change is introduced. The game README is not included or changed.

## Existing test coverage

The public candidate test sources were inspected, but no historical test result is reused as fresh acceptance:

- candidates/actor-status/a6de3fff486d/full13-test-only/tests/test_view_facade.gd:130–148 covers historical receipt binding, duplicate narration, sidecar admission and unchanged pending authority. It does not exercise Main's manual-import display.
- candidates/actor-status/a6de3fff486d/full13-test-only/tests/test_full_main_bridge.gd:347–378 covers speaker/text/tooltip isolation and duplicate history through direct _on_runtime_narration() calls. It pins a different historical Main SHA and cannot certify this exact public-v30 Main. It does not send these narration replies through the manual JSON route.
- candidates/actor-public-v29-compat/05ebbe56e88d/test_finite_main.gd:33–65 and 110–127 exercises actual Main manual proposal/assessment imports, real atomic commits and player-enemy-player return. Its finite route uses the status profile and contains no manual-narration display assertion; it does not certify this actor-v2 regression.

Thus the specific manual-display ownership path is not covered by the inspected existing sources. This is not a claim that every test in the repository was examined.

## Prepared executable regression helpers

tests/test_manual_receipt_display.gd is authored but unparsed and unrun. It is a callable test helper, not a standalone Godot launcher or fixture builder. Invoke it only from an already admitted, isolated real-Main QA fixture that completed an authentic actor_actions_v2 player → single enemy → player round trip with the original source, real Engine and offline transport. Keep the approved resource/process guard and isolated user directory unchanged.

Use fresh round-trip fixtures for these three calls:

1. pending_import(app, committed_player_receipt.action_id, "MANUAL_OLDER_RECEIPT_ONLY")
2. pending_import(app, committed_enemy_receipt.action_id, "MANUAL_LATEST_RECEIPT_WITH_NEW_PENDING")
3. idle_latest_import(app, "MANUAL_LATEST_IDLE_RECEIPT")

The first two start a real new player intent through the Main submit button and then exercise show_import() → import_decision() → apply_decision() → apply_playtest_reply(). They assert that old/latest committed prose goes to history once under the immutable receipt turn, while the new pending action retains speaker/text/tooltip. They also verify an unknown receipt is inert, duplicate imports do not append or promote, the sidecar accepts only the actual receipt, and authority save bytes, current request, active action, phase and accepted-effects counter remain unchanged.

The third checks that the latest idle receipt still promotes all three dialogue controls and that duplicate import remains idempotent. Its initial round-trip receipts must be real and un-narrated. These helpers do not replace the existing round-trip fixture or claim that its execution already occurred.

## Player-visible acceptance scenario

Complete a genuine player action, an independently evaluated enemy action, and return to the player's slot. Submit the player's next intended action so the game displays that intent and waits for its assessment. Manually import correctly bound optional narration for the earlier player receipt.

Expected: the prose appears once in adventure history with that earlier receipt's turn; the current dialogue still shows the new player's intent, including its speaker and tooltip. The new action remains waiting for assessment. No number, turn, die, receipt effect or target changes. Import the same JSON again: no extra history entry or display takeover. Separately, import the latest receipt's prose while idle: it still displays normally as the latest dialogue.

## Checks completed here

- Exact base Main bytes/hash and restored local Main match.
- Only apply_playtest_reply() differs; all other functions and prefix bytes are identical.
- Extracted manual display predicate matches the existing callback predicate across 20 actor/receipt/phase combinations.
- 131 frozen authority dependency hashes and five adapter/controller/narration dependencies match the formal source restoration chain; computed actor profile hash matches the public expected hash.
- Patch --dry-run applies to the exact restored Main.
- No Godot process, new task environment, production-source edit, Git write or model request occurred.

STATIC_CHECKS.json records the source checks and explicitly distinguishes them from unrun Godot/native acceptance. MANIFEST.json pins every delivered file; the regression helper must be parsed and run in an approved isolated QA environment before gameplay acceptance.
