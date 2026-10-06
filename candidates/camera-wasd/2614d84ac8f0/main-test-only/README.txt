WASD real Main event test, candidate only

Use a separate existing public API/P1 test project with Main48 plus the matching one-line WASD patch, yielding exact Main b17a361b0ee8a1c671b90e2bd3a0d5774a373a66ecc618042d2bbf7c8f0aa32c. All required production hashes are in TEST_MANIFEST.json; do not install in the actor combat tree. Keep the existing Full resource guard, exact input hashes and isolated fresh user-data checks. No new launcher or resource bundle is supplied.

Set FOGBANK_WASD_TEST_USER_DIR to exact OS.get_user_data_dir(); optionally set FOGBANK_WASD_TEST_REPORT to a new output path. Run res://tests/camera_wasd/test_main_events.gd once. Expect WASD_MAIN_EVENTS_RESULT, ok=true, 67 checks, no failures, matching real PID/source hashes and strict clean process exit. The test never configures keys or makes HTTP requests.

Real production Main,1801-cell current Bundle, actual Camera3D/rig and actual TextEdit/LineEdit/API Window/PopupMenu are used. InputEventKey objects are dispatched through Input.parse_input_event, not by calling the latch with a false boolean. Only autonomous controller timing is paused to apply a deterministic0.25s dt to its original production _process; that method still queries real physical-key state and real GUI guards. All Engine facts/position/resources/RNG/history must remain byte-exact.

Headless Godot4.6.3 dispatches Input events and reports its OS window focused unconditionally. Thus this validates real in-engine GUI focus/window integration, not OS hardware keys or visual rendering. Window focus-exited is explicitly injected and verifies release/repress behavior only. It is not a genuine OS app switch. Embedded subwindows are enabled only in this test. No screenshot or full visual acceptance claim.
