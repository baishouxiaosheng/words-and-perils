import json,hashlib,shutil,difflib,os
from pathlib import Path
R=Path(__file__).parent;P=Path(r"E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a")
source=P/"public-candidates/natural-save-identity/project";dest=R/"candidate-project"
assert not dest.exists()
for p in [source,*source.rglob("*")]:
    assert not p.is_symlink() and not (os.lstat(p).st_file_attributes & 0x400)
shutil.copytree(source,dest)
fixed=P/"evidence/local-dev-20261008-sol-a1b40/natural-test-type-fix/overlay/tests/natural_coast_basic/test_adapter.gd"
shutil.copyfile(fixed,dest/"tests/natural_coast_basic/test_adapter.gd")
path=dest/"view/generated_natural_coast_basic/adapter.gd";old=path.read_text("utf-8")
new=old.replace('var file := FileAccess.open(path+".tmp",FileAccess.WRITE)','var file := _open_save_temporary(path+".tmp")')
new=new.replace('file.store_string(encoded); file.flush()','var stored: bool = file.store_string(encoded); file.flush()')
new=new.replace('var write_error := file.get_error(); file.close()','var write_error: Error = file.get_error(); file.close()')
new=new.replace('if write_error != OK: return C.fail("SAVE_FAILED"','if not stored or write_error != OK: return C.fail("SAVE_FAILED"')
new=new.replace('if DirAccess.rename_absolute(path+".tmp",path) != OK:','if _rename_save_temporary(path+".tmp",path) != OK:')
seam='''# Virtual I/O boundaries allow deterministic tests of the production save path.
# Normal callers always use the unchanged native file and rename backends.
func _open_save_temporary(path: String) -> RefCounted:
\treturn FileAccess.open(path,FileAccess.WRITE)
func _rename_save_temporary(temporary: String, destination: String) -> Error:
\treturn DirAccess.rename_absolute(temporary,destination)
'''
new=new.replace('func load_file(path: String = "") -> Dictionary:',seam+'func load_file(path: String = "") -> Dictionary:')
assert new!=old and new.count('var stored: bool = file.store_string(encoded)')==1
path.write_text(new,"utf-8",newline="\n")
(R/"SOURCE_DIFF.patch").write_text("".join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile="baseline/view/generated_natural_coast_basic/adapter.gd",tofile="candidate/view/generated_natural_coast_basic/adapter.gd")),"utf-8")
print("Prepared independent Natural project; only adapter production change plus inherited exact Dictionary overlay.")

