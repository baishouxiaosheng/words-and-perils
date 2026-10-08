$ErrorActionPreference='Stop'
$state='E:\WordsAndPerils-Tasks\.local-work-state\repo-1403552519'
$lockStream=$null
try {
 $lockStream=[IO.File]::Open((Join-Path $state 'REPO-WIDE-WRITER.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 [ordered]@{owner_run_id='run-20261008-a1b40-01';pid=$PID;started_utc=[DateTime]::UtcNow.ToString('o');mechanism='exclusive FileShare.None handle across local sessions/worktrees';lock_path=(Join-Path $state 'REPO-WIDE-WRITER.lock')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'LOCK_OWNER.json') -Encoding utf8NoBOM
 Write-Output ('REPO_LOCK_HELD PID='+$PID)
 while(-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'RELEASE_LOCK'))){Start-Sleep -Milliseconds 500}
} finally {
 if($lockStream){$lockStream.Dispose()}
 [ordered]@{pid=$PID;released_utc=[DateTime]::UtcNow.ToString('o');handle_disposed=$true} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'LOCK_RELEASED.json') -Encoding utf8NoBOM
}

