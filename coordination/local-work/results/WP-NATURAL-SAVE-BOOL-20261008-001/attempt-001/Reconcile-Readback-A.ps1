$ErrorActionPreference='Stop'
$prep=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'PHASE_A_PREPARED.json') -Raw | ConvertFrom-Json -DateKind String
$old=Join-Path $PSScriptRoot 'remote-readback-A'
$new=Join-Path $PSScriptRoot 'remote-readback-A-missing-once'
if(Test-Path -LiteralPath $new){throw 'Preserve prior reconciliation; no repeated attempt'}
[IO.Directory]::CreateDirectory($new) | Out-Null
$headers=@{'User-Agent'='WordsAndPerils-exact-readback';'Cache-Control'='no-cache'}
$tree=Invoke-RestMethod -Uri ('https://api.github.com/repos/baishouxiaosheng/words-and-perils/git/trees/'+$prep.commit+'?recursive=1') -Headers $headers -TimeoutSec 20
if($tree.truncated -ne $false){throw 'Incomplete remote tree'}
$map=@{};foreach($r in $tree.tree){$map[$r.path]=$r}
$rows=@();$retryCount=0
foreach($r in $prep.files){
 if($r.path -match '[\x00-\x1f\x7f\\:]' -or $r.path.Split('/') -contains '..'){throw 'Unsafe path'}
 if($map[$r.path].mode -ne '100644' -or $map[$r.path].sha -cne $r.git_blob_sha){throw 'Remote tree mismatch'}
 $p=Join-Path $old $r.path
 if(-not (Test-Path -LiteralPath $p) -or (Get-Item -LiteralPath $p).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $r.sha256){
  $retryCount++
  if($retryCount -gt 1){throw 'More missing files than read-only reconciliation established'}
  $p=[IO.Path]::GetFullPath((Join-Path $new $r.path))
  if(-not $p.StartsWith($new+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Path containment failed'}
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p)) | Out-Null
  Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/baishouxiaosheng/words-and-perils/'+$prep.commit+'/'+$r.path) -OutFile $p -TimeoutSec 60 -ErrorAction Stop
 }
 $b=[IO.File]::ReadAllBytes($p)
 $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b)).ToLowerInvariant()
 $blob=[Convert]::ToHexString([Security.Cryptography.SHA1]::HashData([byte[]]([Text.Encoding]::UTF8.GetBytes('blob '+$b.Length+[char]0)+$b))).ToLowerInvariant()
 if($b.Length -ne $r.bytes -or $hash -cne $r.sha256 -or $blob -cne $r.git_blob_sha){throw 'Actual remote bytes mismatch'}
 $rows += [ordered]@{path=$r.path;bytes=$b.Length;sha256=$hash;git_blob_sha=$blob;bytes_match=$true;sha256_match=$true;blob_match=$true;source='Actual immutable raw HTTP bytes, retained from first attempt or one missing-file read';verified_utc=[DateTime]::UtcNow.ToString('o')}
}
[ordered]@{phase='A';commit=$prep.commit;expected_files=$prep.files.Count;readback_files=$rows.Count;all_match=($rows.Count -eq $prep.files.Count);remote_tree_truncated=$false;initial_failure='One 25-second raw HTTP timeout; 166 complete matching returns retained; missing file retried once after read-only reconciliation';missing_file_reads=$retryCount;files=$rows;checked_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'REMOTE_READBACK_A.json') -Encoding utf8NoBOM
[ordered]@{phase='A';commit=$prep.commit;readback_files=$rows.Count;all_match=$true} | ConvertTo-Json
