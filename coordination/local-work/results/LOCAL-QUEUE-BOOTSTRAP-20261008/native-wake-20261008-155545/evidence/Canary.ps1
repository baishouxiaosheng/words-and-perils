$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$exe=(Get-Command codex -ErrorAction Stop).Source
& $exe --version 1> (Join-Path $root 'CLI_VERSION.stdout.log') 2> (Join-Path $root 'CLI_VERSION.stderr.log')
& $exe exec --help 1> (Join-Path $root 'CLI_EXEC_HELP.stdout.log') 2> (Join-Path $root 'CLI_EXEC_HELP.stderr.log')
& $exe exec resume --help 1> (Join-Path $root 'CLI_RESUME_HELP.stdout.log') 2> (Join-Path $root 'CLI_RESUME_HELP.stderr.log')
$utc=[DateTime]::UtcNow.ToString('o')
$prompt='This is the explicitly authorized NON-GAME worker canary. Do not use any tools, access game files, read credentials, write or modify files, or start other workers. Output exactly two lines: NON_GAME_WORKER_CANARY_OK then the supplied actual launch UTC timestamp '+$utc+'. End immediately.'
$info=[Diagnostics.ProcessStartInfo]::new()
$info.FileName=$exe;$info.WorkingDirectory=$root;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
foreach($arg in @('exec','--ephemeral','--sandbox','read-only','--skip-git-repo-check','--color','never','--json','-m','gpt-6.1-sol',$prompt)){$info.ArgumentList.Add($arg)}
$p=[Diagnostics.Process]::new();$p.StartInfo=$info
$receipt=[ordered]@{kind='non_game_worker_canary';version=(Get-Content -LiteralPath (Join-Path $root 'CLI_VERSION.stdout.log') -Raw).Trim();model='gpt-6.1-sol';interface='codex exec';ephemeral=$true;requested_sandbox='read-only';timeout_seconds=120;launch_utc=$utc;game_execution=$false;worker_file_modifications_authorized=$false;credentials_created_or_exported=$false}
try{
 if(-not $p.Start()){throw 'Canary process did not start'}
 $receipt.pid=$p.Id;$receipt.process_created_utc=$p.StartTime.ToUniversalTime().ToString('o')
 $out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
 $finished=$p.WaitForExit(120000);$receipt.timed_out=-not $finished
 if(-not $finished){$p.Kill($true);$p.WaitForExit(10000) | Out-Null}
 if(-not $out.Wait(10000) -or -not $err.Wait(10000)){throw 'Owned reader did not finish'}
 [IO.File]::WriteAllText((Join-Path $root 'CANARY.stdout.log'),$out.Result)
 [IO.File]::WriteAllText((Join-Path $root 'CANARY.stderr.log'),$err.Result)
 $receipt.exit_code=$p.ExitCode;$receipt.process_exited=$p.HasExited;$receipt.readers_finished=$true
 $events=@($out.Result.Split([char]10) | Where-Object {$_.Trim()} | ForEach-Object {$_ | ConvertFrom-Json -DateKind String})
 $messages=@($events | Where-Object {$_.type -eq 'item.completed' -and $_.item.type -eq 'agent_message'} | ForEach-Object {$_.item.text})
 $receipt.agent_messages=$messages;$receipt.command_execution_items=@($events | Where-Object {$_.item.type -eq 'command_execution'}).Count
 $receipt.token_present=(@($messages | Where-Object {$_ -match '^NON_GAME_WORKER_CANARY_OK\r?\n'}).Count -eq 1)
 $receipt.passed=($finished -and $p.ExitCode -eq 0 -and $receipt.token_present -and $receipt.command_execution_items -eq 0)
}catch{$receipt.error=$_.Exception.Message;$receipt.passed=$false}finally{
 if($p.Id -and -not $p.HasExited){$p.Kill($true);$p.WaitForExit(10000) | Out-Null}
 $p.Dispose();$receipt.handle_disposed=$true;$receipt.ended_utc=[DateTime]::UtcNow.ToString('o')
 $receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $root 'CANARY_RESULT.json') -Encoding utf8NoBOM
}
$receipt | ConvertTo-Json -Depth 10
if(-not $receipt.passed){exit 1}
