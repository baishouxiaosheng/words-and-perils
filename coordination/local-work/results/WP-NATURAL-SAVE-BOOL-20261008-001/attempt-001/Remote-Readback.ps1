param([Parameter(Mandatory=$true)][string]$PreparedFile,[Parameter(Mandatory=$true)][string]$Phase)
$ErrorActionPreference='Stop'
$prep=Get-Content -LiteralPath (Join-Path $PSScriptRoot $PreparedFile) -Raw | ConvertFrom-Json -DateKind String
$root=Join-Path $PSScriptRoot ('remote-readback-'+$Phase)
if(Test-Path -LiteralPath $root){throw 'Readback directory exists; preserve prior receipt'}
[IO.Directory]::CreateDirectory($root) | Out-Null
$headers=@{'User-Agent'='WordsAndPerils-exact-readback';'Cache-Control'='no-cache'}
$tree=Invoke-RestMethod -Uri ('https://api.github.com/repos/baishouxiaosheng/words-and-perils/git/trees/'+$prep.commit+'?recursive=1') -Headers $headers -TimeoutSec 20
if($tree.truncated -ne $false){throw 'Remote tree truncated'}
$remote=@{}
foreach($entry in $tree.tree){$remote[$entry.path]=$entry}
foreach($row in $prep.files){if(-not $remote.ContainsKey($row.path) -or $remote[$row.path].mode -ne '100644' -or $remote[$row.path].sha -ne $row.git_blob_sha){throw 'Remote mode/blob mismatch'}}
$commit=$prep.commit
$rows=@($prep.files | ForEach-Object -ThrottleLimit 6 -Parallel {
 $row=$_
 $readRoot=$using:root
 $sha=$using:commit
 $path=$row.path
 if($path -match '[\x00-\x1f\x7f\\:]' -or $path.StartsWith('/') -or $path.Split('/') -contains '..'){throw 'Readback path unsafe'}
 $out=[IO.Path]::GetFullPath((Join-Path $readRoot $path))
 if(-not $out.StartsWith([IO.Path]::GetFullPath($readRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Readback path escapes root'}
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($out)) | Out-Null
 Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/baishouxiaosheng/words-and-perils/'+$sha+'/'+$path) -OutFile $out -TimeoutSec 25 -ErrorAction Stop
 $bytes=[IO.File]::ReadAllBytes($out)
 $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
 $blob=[Convert]::ToHexString([Security.Cryptography.SHA1]::HashData([byte[]]([Text.Encoding]::UTF8.GetBytes('blob '+$bytes.Length+[char]0)+$bytes))).ToLowerInvariant()
 [ordered]@{path=$path;bytes=$bytes.Length;sha256=$hash;git_blob_sha=$blob;bytes_match=$bytes.Length -eq $row.bytes;sha256_match=$hash -ceq $row.sha256;blob_match=$blob -ceq $row.git_blob_sha;source='actual HTTP raw bytes at immutable remote commit';verified_utc=[DateTime]::UtcNow.ToString('o')}
})
$all=$rows.Count -eq $prep.files.Count -and @($rows | Where-Object {-not $_.bytes_match -or -not $_.sha256_match -or -not $_.blob_match}).Count -eq 0
[ordered]@{phase=$Phase;commit=$commit;expected_files=$prep.files.Count;readback_files=$rows.Count;all_match=$all;remote_tree_truncated=$tree.truncated;files=$rows;checked_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $PSScriptRoot ('REMOTE_READBACK_'+$Phase+'.json')) -Encoding utf8NoBOM
[ordered]@{phase=$Phase;commit=$commit;readback_files=$rows.Count;all_match=$all} | ConvertTo-Json
if(-not $all){throw 'Remote readback did not verify every artifact'}

