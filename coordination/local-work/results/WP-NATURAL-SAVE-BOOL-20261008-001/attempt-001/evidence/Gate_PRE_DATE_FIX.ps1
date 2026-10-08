param([Parameter(Mandatory=$true)][string]$Boundary,[switch]$Preclaim)
$ErrorActionPreference='Stop'
$run=$PSScriptRoot
$state='E:\WordsAndPerils-Tasks\.local-work-state\repo-1403552519'
function TaskHash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function StrictJSON([string]$Text) {
 $doc=[System.Text.Json.JsonDocument]::Parse($Text)
 function CheckNode($node) {
  if($node.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
   $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
   foreach($p in $node.EnumerateObject()){if(-not $seen.Add($p.Name)){throw 'Duplicate JSON key'};CheckNode $p.Value}
  } elseif($node.ValueKind -eq [System.Text.Json.JsonValueKind]::Array){foreach($n in $node.EnumerateArray()){CheckNode $n}}
 }
 try{CheckNode $doc.RootElement}finally{$doc.Dispose()}
 return ($Text | ConvertFrom-Json -AsHashtable -Depth 100)
}
function SafePath([string]$p) {
 if([string]::IsNullOrWhiteSpace($p) -or $p -match '[\x00-\x1f\x7f\\:]' -or $p.StartsWith('/')){throw 'Unsafe relative path'}
 foreach($part in $p.Split('/')){if($part -in @('','.', '..','.git','.github','README','README.md')){throw 'Forbidden path segment'}}
}
$stamp=[DateTime]::UtcNow.ToString('o')
$receipt=[ordered]@{boundary=$Boundary;started_utc=$stamp;local_stop=(Join-Path $state 'STOP');passed=$false}
try {
 if(Test-Path -LiteralPath (Join-Path $state 'STOP-LATCH.json')){throw 'Stop is already latched; direct owner resume required'}
 if(Test-Path -LiteralPath (Join-Path $state 'STOP')){throw 'Trusted local STOP present'}
 $config=StrictJSON ([IO.File]::ReadAllText((Join-Path $state 'TRUSTED_CONFIG.json')))
 if($config.task_id -ne 'WP-NATURAL-SAVE-BOOL-20261008-001' -or $config.execution_mode -ne 'single_task_only'){throw 'Trusted config mismatch'}
 $lockOwner=StrictJSON ([IO.File]::ReadAllText((Join-Path $run 'LOCK_OWNER.json')))
 $lockProcess=Get-Process -Id $lockOwner.pid -ErrorAction Stop
 if($lockOwner.owner_run_id -cne $config.owner_run_id -or $lockProcess.StartTime.ToUniversalTime().ToString('o') -cne $lockOwner.process_created_utc){throw 'Local lock owner/process identity changed'}
 $lockProbe=$null;$lockHeld=$false
 try{$lockProbe=[IO.File]::Open((Join-Path $state 'REPO-WIDE-WRITER.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{$lockHeld=$true}finally{if($lockProbe){$lockProbe.Dispose()}}
 if(-not $lockHeld){throw 'Repository-wide lock is not held'}
 $receipt['local_lock_held']= $true
 $headers=@{'User-Agent'='WordsAndPerils-local-writer';'Accept'='application/vnd.github+json';'Cache-Control'='no-cache'}
 $head=Invoke-RestMethod -Uri 'https://api.github.com/repos/baishouxiaosheng/words-and-perils/git/ref/heads/main' -Headers $headers -TimeoutSec 20
 if($head.object.type -ne 'commit' -or $head.object.sha -notmatch '^[0-9a-f]{40}$'){throw 'Invalid main reference'}
 $receipt['head']=$head.object.sha
 $tree=Invoke-RestMethod -Uri ('https://api.github.com/repos/baishouxiaosheng/words-and-perils/git/trees/'+$head.object.sha+'?recursive=1') -Headers $headers -TimeoutSec 20
 if($tree.truncated -ne $false){throw 'Unknown STOP due to incomplete tree'}
 if(@($tree.tree | Where-Object path -eq 'coordination/local-work/STOP').Count){throw 'Remote STOP present'}
 $receipt['remote_stop_absent']=$true
 $expected=[ordered]@{'coordination/local-work/PROTOCOL.json'=$config.protocol_sha256;'coordination/local-work/TASK_SCHEMA.json'=$config.schema_sha256;'coordination/local-work/inbox/WP-NATURAL-SAVE-BOOL-20261008-001.json'=$config.task_sha256}
 $values=@{}
 foreach($path in @($expected.Keys)+@('coordination/local-work/CONTROL.json')){
  SafePath $path
  $item=@($tree.tree | Where-Object path -eq $path)
  if($item.Count -ne 1 -or $item[0].type -ne 'blob' -or $item[0].mode -ne '100644'){throw ('Missing or unsafe gate file '+$path)}
  $response=Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/baishouxiaosheng/words-and-perils/'+$head.object.sha+'/'+$path) -Headers @{'Cache-Control'='no-cache'} -TimeoutSec 20
  $bytes=[byte[]]$response.RawContentStream.ToArray()
  $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
  $blob=[Convert]::ToHexString([Security.Cryptography.SHA1]::HashData([byte[]]([Text.Encoding]::UTF8.GetBytes("blob "+$bytes.Length+[char]0)+$bytes))).ToLowerInvariant()
  if($blob -ne $item[0].sha){throw 'Remote bytes/tree blob mismatch'}
  if($expected.Contains($path) -and $hash -ne $expected[$path]){throw ('Pinned file changed '+$path)}
  $values[$path]=StrictJSON ([Text.Encoding]::UTF8.GetString($bytes))
 }
 $control=$values['coordination/local-work/CONTROL.json']
 $keys=@('protocol','kind','queue_enabled','stop','resume_generation','reason')
 if($control.Count -ne 6 -or @($control.Keys | Where-Object {$_ -notin $keys}).Count){throw 'Unknown CONTROL fields'}
 if($control.protocol -cne 'words-and-perils-local-work/v1' -or $control.kind -cne 'control' -or $control.queue_enabled -isnot [bool] -or $control.stop -isnot [bool] -or ($control.resume_generation -isnot [int] -and $control.resume_generation -isnot [long]) -or $control.resume_generation -lt 0 -or $control.reason -isnot [string]){throw 'CONTROL exact type validation failed'}
 $receipt['control']=$control
 if($control.stop -or -not $control.queue_enabled){throw 'CONTROL disabled/stopped'}
 if($Preclaim){
  if(@($tree.tree | Where-Object {$_.path -like 'coordination/local-work/results/WP-NATURAL-SAVE-BOOL-20261008-001/*'}).Count){throw 'Existing remote task state; reconcile before claim'}
 } else {
  $claimPath='coordination/local-work/results/WP-NATURAL-SAVE-BOOL-20261008-001/CLAIM.json'
  $item=@($tree.tree | Where-Object path -eq $claimPath)
  if($item.Count -ne 1 -or $item[0].mode -ne '100644'){throw 'Claim missing or unsafe'}
  $claim=Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/baishouxiaosheng/words-and-perils/'+$head.object.sha+'/'+$claimPath) -TimeoutSec 20
  $claimBytes=[byte[]]$claim.RawContentStream.ToArray()
  $claimHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($claimBytes)).ToLowerInvariant()
  if($claimHash -ne (TaskHash (Join-Path $run 'CLAIM.json'))){throw 'Claim ownership/content changed'}
  $claimValue=StrictJSON ([Text.Encoding]::UTF8.GetString($claimBytes))
  if($claimValue.owner_run_id -cne $config.owner_run_id -or $claimValue.task_sha256 -cne $config.task_sha256){throw 'Wrong claim owner'}
  $receipt['claim_sha256']=$claimHash
 }
 if(Test-Path -LiteralPath (Join-Path $state 'STOP')){throw 'Trusted local STOP appeared during gate'}
 $receipt['passed']=$true;$receipt['tree_sha']=$tree.sha
 $receipt['ended_utc']=[DateTime]::UtcNow.ToString('o')
 $out=Join-Path $run ('gates/GATE-'+$Boundary+'-'+[Guid]::NewGuid().ToString('N')+'.json')
 $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $out -Encoding utf8NoBOM
 $receipt | ConvertTo-Json -Depth 12
} catch {
 $receipt['error']=$_.Exception.Message
 $receipt['ended_utc']=[DateTime]::UtcNow.ToString('o')
 $out=Join-Path $run ('gates/GATE-'+$Boundary+'-'+[Guid]::NewGuid().ToString('N')+'.json')
 $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $out -Encoding utf8NoBOM
 if(-not (Test-Path -LiteralPath (Join-Path $state 'STOP-LATCH.json'))){$receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $state 'STOP-LATCH.json') -Encoding utf8NoBOM}
 throw
}

