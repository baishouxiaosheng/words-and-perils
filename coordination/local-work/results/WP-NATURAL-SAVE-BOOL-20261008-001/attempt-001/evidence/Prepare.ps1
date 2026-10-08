param([Parameter(Mandatory=$true)][string]$RunName,[Parameter(Mandatory=$true)][ValidateSet('compile','focused','adapter')][string]$Suite,[string]$Recipe='')
$ErrorActionPreference='Stop'
$runRoot=Join-Path $PSScriptRoot $RunName
if(Test-Path -LiteralPath $runRoot){throw 'Run already exists'}
if(Get-Process -Name '*Godot*' -ErrorAction SilentlyContinue){throw 'Unknown Godot found; no launch'}
$source=Join-Path $PSScriptRoot 'candidate-project'
$project=Join-Path $runRoot 'project'
New-Item -ItemType Directory -Path $runRoot | Out-Null
Copy-Item -LiteralPath $source -Destination $project -Recurse
foreach($leaf in @('data','data/appdata','data/localappdata','data/temp','output')){New-Item -ItemType Directory -Path (Join-Path $runRoot $leaf) | Out-Null}
$baseline=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'CANDIDATE_SOURCE_MAP.json') -Raw | ConvertFrom-Json
$rows=@(foreach($b in $baseline){$s=(Get-FileHash -LiteralPath (Join-Path $source $b.path)).Hash.ToLowerInvariant();$c=(Get-FileHash -LiteralPath (Join-Path $project $b.path)).Hash.ToLowerInvariant();if($s -ne $b.sha256 -or $c -ne $s){throw 'Candidate/copy changed'};[ordered]@{path=$b.path;copy_sha256=$c;source_sha256=$s}})
$suitePath=switch($Suite){'compile'{'tests/natural_coast_basic/test_compile.gd'};'adapter'{'tests/natural_coast_basic/test_adapter.gd'};'focused'{'tests/t03_natural_write_result/test_save_file.gd'}}
if((Get-Content -LiteralPath (Join-Path $project 'project.godot') -Raw) -match '(?m)^\[autoload\]'){throw 'Autoload found'}
$entry=@'
extends "res://SUITE_PATH"
func _initialize() -> void:
	var root := OS.get_cmdline_user_args()[0].replace("\\", "/").simplify_path().trim_suffix("/")
	var os_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path().trim_suffix("/")
	var global_dir := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/")
	var autoloads: Array = []
	for p in ProjectSettings.get_property_list():
		if str(p.name).begins_with("autoload/"): autoloads.append(p.name)
	var isolated := os_dir.to_lower().begins_with((root+"/appdata/Godot/app_userdata/").to_lower()) and os_dir.to_lower()==global_dir.to_lower() and autoloads.is_empty()
	print("LOCAL_SUITE_ISOLATION ",JSON.stringify({"isolated":isolated,"os_user_dir":os_dir,"globalized_user_dir":global_dir,"autoloads":autoloads,"run_id":"RUN_NAME"}))
	if not isolated:
		quit(3)
		return
	OS.set_environment("COAST_PLAY_RECIPE","RECIPE_NAME")
	OS.set_environment("COAST_PLAY_RUN_ID","RUN_NAME")
	OS.set_environment("COAST_PLAY_OUTPUT","OUTPUT_PATH")
	super._initialize()
'@
$entry=$entry.Replace('SUITE_PATH',$suitePath).Replace('RUN_NAME',$RunName).Replace('RECIPE_NAME',$Recipe).Replace('OUTPUT_PATH',(Join-Path $runRoot 'output').Replace('\','/'))
if($Suite -eq 'adapter'){
$observer=@'

func check(ok: bool, label_: String) -> bool:
	var result := super.check(ok,label_)
	if label_.begins_with("T03 "):
		print("T03_EXECUTED ",JSON.stringify({"label":label_,"passed":ok}))
	return result
'@
$entry+=$observer
}
$entryPath='tests/t03_natural_write_result/_local_entry.gd'
[IO.File]::WriteAllText((Join-Path $project $entryPath),$entry.Replace([string][char]13,'')+[char]10,[Text.UTF8Encoding]::new($false))
$entryHash=(Get-FileHash -LiteralPath (Join-Path $project $entryPath)).Hash.ToLowerInvariant()
$rows+=,[ordered]@{path=$entryPath;copy_sha256=$entryHash;source_sha256=$entryHash;generated_isolation_wrapper=$true}
$rows | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'SOURCE_MAP.json') -Encoding utf8NoBOM
[ordered]@{candidate='natural-save-identity';suite=$suitePath;recipe=$Recipe;run_id=$RunName;source=$source;project=$project;suite_sha256=(Get-FileHash -LiteralPath (Join-Path $project $suitePath)).Hash.ToLowerInvariant();entry_sha256=$entryHash;scope='Fresh exact independent Natural candidate; actual changed adapter; inherited identity engine + exact Dictionary suite; no Raw; isolated data; no autoload';source_files=$rows.Count} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'PREPARATION.json') -Encoding utf8NoBOM
[ordered]@{executable='E:\WordsAndPerils-Test\Godot\4.6.3\Godot_v4.6.3-stable_win64.exe';arguments=@('--headless','--path',$project,'--script',('res://'+$entryPath),'--',(Join-Path $runRoot 'data'));working_directory=$project;isolated_data_root=(Join-Path $runRoot 'data');profile='small';timeout_seconds=120;log_path=(Join-Path $runRoot 'GUARD_RESULT.json')} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'SPEC.json') -Encoding utf8NoBOM
Write-Output ('Prepared '+$RunName+'; source files='+$rows.Count)

