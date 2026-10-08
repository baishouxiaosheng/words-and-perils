from pathlib import Path
R=Path(__file__).parent
p=R/"Audit-Test.ps1";s=p.read_text("utf-8-sig")
s=s.replace("$suiteLines=@($lines | Where-Object {$_ -like 'NATURAL_COAST_BASIC *'})","$prefix=if($prep.suite -eq 'tests/t03_natural_write_result/test_save_file.gd') {'NATURAL_WRITE_RESULT '} else {'NATURAL_COAST_BASIC '}\n $suiteLines=@($lines | Where-Object {$_.StartsWith($prefix)})")
s=s.replace("$suiteLines[0].Substring('NATURAL_COAST_BASIC '.Length)","$suiteLines[0].Substring($prefix.Length)")
anchor="if($prep.suite -like '*test_adapter.gd') {$strict=$strict -and $t03.Count -eq 13 -and @($t03 | Where-Object {-not $_.passed}).Count -eq 0}"
s=s.replace(anchor,anchor+"\nif($prep.suite -like '*test_compile.gd') {$strict=$strict -and $suiteResult.checks -eq 4}\nif($prep.suite -like '*test_adapter.gd') {$strict=$strict -and $suiteResult.checks -eq 170}\nif($prep.suite -eq 'tests/t03_natural_write_result/test_save_file.gd') {$strict=$strict -and $suiteResult.cases.Count -eq 5 -and @($suiteResult.cases | Where-Object {-not $_.passed}).Count -eq 0}")
p.write_text(s,"utf-8",newline="\n")

