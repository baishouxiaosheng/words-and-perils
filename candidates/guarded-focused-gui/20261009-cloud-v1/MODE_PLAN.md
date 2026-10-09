# Focused GUI source candidate

Implemented, not deployed: `WindowsGuard.FocusedGui.cs`, real source diff
`WindowsGuard.FocusedGui.patch`, and `Invoke-FocusedGuiGuard.ps1`.
The exact original v3 guard/wrapper remain under `baseline/`.

Default invocation uses `-SpecPath` and remains headless. GUI requires the
separate parameter set `-OwnerGuiSpecPath -FocusedGui -OwnerGodotSha256
-OwnerRunId`, supplied explicitly by the supported local owner entry. Ordinary
SPEC/ready fields cannot select mode or supply the executable pin. No trusted
configuration, queue, scheduler, OS permission, service or credential is changed.

GUI is limited to official Godot 4.6.3's exact filename plus the owner-provided
trusted SHA, the fixed 18-file native010 fixture hashes, and the exact eight GUI
argument tokens. It requires small/1024 MiB/120s/64 KiB output, fresh isolated
user directories and a fresh cache; rejects alternate commands, scripts, extra
arguments, reparse paths, overlapping roots and self-test faults. Input read
leases deny writes/deletes until all native cleanup finishes. GUI changes only
visibility flags while sharing the original Job/monitor/termination body.

Cloud: packaged source/patch checks are recorded in SOURCE_TEST_RESULT.json. The original native Run
body and all other original guard code are exactly recoverable by reversing the
nine declared source edits. The package omits the original native starter and private input snapshot.
Its source check differs from the initial local check only by omitting the
original starter hash check; C# candidate and source diff bytes are unchanged.

Local source-only compilation/test (no Guard.Run and no engine):
`pwsh -NoProfile -File ./Test-FocusedGui.SourceOnly.ps1`
This test compiles the actual candidate and original source, compares admission
calculations, and invokes managed flag/validation methods. It has not run here:
there is no installed C#/PowerShell compiler. No undefined owner-policy API or
external package is required by the C# candidate.

Before native adoption, the supported local owner must review/build and verify
trusted Godot SHA, ownership/input directory boundary, held existing repository
lock and live STOP/network/claim gates. Keep the existing guarded starter's
before/after hashes, owner PID+creation time, both isolation APIs before body,
exit-code and complete ERROR/WARNING scans, packet/frame checks and lock release.
The new wrapper is not a substitute for those existing orchestration checks.
Then separately authorize complete native protection acceptance for both modes:
Job memory/readback, reserve/AvailPhys, timeout, output/readers, descendants and
terminal cleanup. No task010 rerun is authorized. Committed memory is not VRAM;
actual GUI/capture and Win32 equivalence remain unverified. No engine has started.
