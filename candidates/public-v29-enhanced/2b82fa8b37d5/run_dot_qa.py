#!/usr/bin/env python3
"""Native dot QA orchestration only. Existing restoration and gameplay fixtures remain authoritative.
Adds no restore algorithm or production behavior. Godot is admitted by the unchanged approved effective8 guard.
"""
from pathlib import Path, PurePosixPath
import base64, hashlib, io, json, os, re, shutil, stat, subprocess, sys, tempfile, time, zipfile
ROOT=Path(__file__).resolve().parents[3]
PREFIX=ROOT/'candidates/public-v29-enhanced/2b82fa8b37d5'
E=ROOT/'artifacts/dot_native_qa_20261007'
MANIFEST_SHA='9a03c2cd673ee53f190dda4d5300608bdf7640b81af5fe428c87550be64bd1e0'
MAIN_SHA='6e2f62e76db2f4a64a9bbdf4d348a32588d1cb991e6d869bff4c730e12e61e5c'
GUARD_BYTES=base64.b64decode('IyEvdXNyL2Jpbi9lbnYgcHl0aG9uMwoiIiJCb3VuZCBvbmUgbmV3bHkgbGF1bmNoZWQgR29kb3QgY2hpbGQgYnkgdGltZSBhbmQgdHJ1ZSBjZ3JvdXAgaGVhZHJvb20uCgpOZXZlciBzaWduYWxzIGEgcGxhdGZvcm0gcHJvY2VzcyBvciBhIHByb2Nlc3MgZ3JvdXAuIEJlZm9yZSBldmVyeSBzaWduYWwgaXQKdmVyaWZpZXMgdGhlIG93bmVkIFBJRCdzIGV4ZWN1dGFibGUsIHBhcmVudCBhbmQgc3RhcnQtdGltZSBpZGVudGl0eS4KIiIiCmltcG9ydCBhcmdwYXJzZQppbXBvcnQganNvbgppbXBvcnQgb3MKaW1wb3J0IHNodXRpbAppbXBvcnQgc2lnbmFsCmltcG9ydCBzdWJwcm9jZXNzCmltcG9ydCBzeXMKaW1wb3J0IHRpbWUKZnJvbSBwYXRobGliIGltcG9ydCBQYXRoCgpwYXJzZXIgPSBhcmdwYXJzZS5Bcmd1bWVudFBhcnNlcigpCnBhcnNlci5hZGRfYXJndW1lbnQoJy0tbG9nJywgdHlwZT1QYXRoLCByZXF1aXJlZD1UcnVlKQpwYXJzZXIuYWRkX2FyZ3VtZW50KCctLXRpbWVvdXQnLCB0eXBlPWZsb2F0LCBkZWZhdWx0PTE4MC4wKQpwYXJzZXIuYWRkX2FyZ3VtZW50KCctLXJlc2VydmUtbWliJywgdHlwZT1pbnQsIGRlZmF1bHQ9NTEyKQpwYXJzZXIuYWRkX2FyZ3VtZW50KCctLWFkbWlzc2lvbi1leHRyYS1taWInLCB0eXBlPWludCwgcmVxdWlyZWQ9VHJ1ZSkKcGFyc2VyLmFkZF9hcmd1bWVudCgnY29tbWFuZCcsIG5hcmdzPWFyZ3BhcnNlLlJFTUFJTkRFUikKYXJncyA9IHBhcnNlci5wYXJzZV9hcmdzKCkKY29tbWFuZCA9IGFyZ3MuY29tbWFuZFsxOl0gaWYgYXJncy5jb21tYW5kWzoxXSA9PSBbJy0tJ10gZWxzZSBhcmdzLmNvbW1hbmQKaWYgbm90IGNvbW1hbmQ6CiAgICByYWlzZSBTeXN0ZW1FeGl0KCdBIEdvZG90IGNvbW1hbmQgaXMgcmVxdWlyZWQnKQpleGVjdXRhYmxlID0gUGF0aChzaHV0aWwud2hpY2goY29tbWFuZFswXSkgb3IgY29tbWFuZFswXSkucmVzb2x2ZShzdHJpY3Q9VHJ1ZSkKaWYgJ2dvZG90JyBub3QgaW4gZXhlY3V0YWJsZS5uYW1lLmxvd2VyKCk6CiAgICByYWlzZSBTeXN0ZW1FeGl0KCdPbmx5IGFuIGV4cGxpY2l0bHkgb3duZWQgR29kb3QgZXhlY3V0YWJsZSBpcyBzdXBwb3J0ZWQnKQpjb21tYW5kWzBdID0gc3RyKGV4ZWN1dGFibGUpCmNncm91cCA9IFBhdGgoJy9zeXMvZnMvY2dyb3VwJykKcGh5c2ljYWxfbGltaXQgPSBpbnQoKGNncm91cCAvICdtZW1vcnkubWF4JykucmVhZF90ZXh0KCkpCmlmIHBoeXNpY2FsX2xpbWl0IDw9IDA6CiAgICByYWlzZSBTeXN0ZW1FeGl0KCdBIHZlcmlmaWVkIHBvc2l0aXZlIHBoeXNpY2FsIGNncm91cCBsaW1pdCBpcyByZXF1aXJlZCcpCmxpbWl0ID0gbWluKHBoeXNpY2FsX2xpbWl0LCA4ICogMTAyNCoqMykKaWYgYXJncy5yZXNlcnZlX21pYiA8IDUxMiBvciBhcmdzLmFkbWlzc2lvbl9leHRyYV9taWIgPCAxMDI0IG9yIG5vdCAwIDwgYXJncy50aW1lb3V0IDw9ICgxODAgaWYgYXJncy5hZG1pc3Npb25fZXh0cmFfbWliID49IDE3NDEgZWxzZSAxMjApOgogICAgcmFpc2UgU3lzdGVtRXhpdCgnUmVzZXJ2ZS9hZG1pc3Npb24vdGltZW91dCBtYXkgbm90IHdlYWtlbiB0aGlzIHZlcmlmaWNhdGlvbiBnYXRlJykKZm9yIHByb2MgaW4gUGF0aCgnL3Byb2MnKS5pdGVyZGlyKCk6CiAgICBpZiBwcm9jLm5hbWUuaXNkaWdpdCgpOgogICAgICAgIHRyeToKICAgICAgICAgICAgaWYgJ2dvZG90JyBpbiAocHJvYyAvICdjb21tJykucmVhZF90ZXh0KCkubG93ZXIoKToKICAgICAgICAgICAgICAgIHJhaXNlIFN5c3RlbUV4aXQoJ0Fub3RoZXIgZW5naW5lIGlzIGFscmVhZHkgcnVubmluZzogJyArIHByb2MubmFtZSkKICAgICAgICBleGNlcHQgKEZpbGVOb3RGb3VuZEVycm9yLCBQZXJtaXNzaW9uRXJyb3IpOgogICAgICAgICAgICBwYXNzCnRocmVzaG9sZCA9IGxpbWl0IC0gYXJncy5yZXNlcnZlX21pYiAqIDEwMjQqKjIKYXJncy5sb2cucGFyZW50Lm1rZGlyKHBhcmVudHM9VHJ1ZSwgZXhpc3Rfb2s9VHJ1ZSkKbG9nID0gYXJncy5sb2cub3BlbigndycsIGJ1ZmZlcmluZz0xKQpzdGFydCA9IHRpbWUubW9ub3RvbmljKCkKY2hpbGQgPSBOb25lCmlkZW50aXR5ID0gTm9uZQoKZGVmIGVtaXQoZXZlbnQsICoqZmllbGRzKToKICAgIHJvdyA9IHsnZXZlbnQnOiBldmVudCwgJ2VsYXBzZWRfcyc6IHJvdW5kKHRpbWUubW9ub3RvbmljKCkgLSBzdGFydCwgNCksICd1dGNfZXBvY2gnOiB0aW1lLnRpbWUoKSwgKipmaWVsZHN9CiAgICBsb2cud3JpdGUoanNvbi5kdW1wcyhyb3cpICsgJ1xuJyk7IGxvZy5mbHVzaCgpCiAgICBpZiBldmVudCAhPSAnc2FtcGxlJzogcHJpbnQoJ09XTkVEX0dPRE9UX0dVQVJEJywganNvbi5kdW1wcyhyb3cpLCBmbHVzaD1UcnVlKQoKZGVmIG1lbW9yeSgpOgogICAgcmV0dXJuIGludCgoY2dyb3VwIC8gJ21lbW9yeS5jdXJyZW50JykucmVhZF90ZXh0KCkpCgpkZWYgb3duZWRfaWRlbnRpdHkoKToKICAgIGlmIGNoaWxkIGlzIE5vbmUgb3IgY2hpbGQucG9sbCgpIGlzIG5vdCBOb25lOiByZXR1cm4gTm9uZQogICAgcHJvYyA9IFBhdGgoJy9wcm9jJykgLyBzdHIoY2hpbGQucGlkKQogICAgdHJ5OgogICAgICAgIGV4ZSA9IFBhdGgob3MucmVhZGxpbmsocHJvYyAvICdleGUnKSkucmVzb2x2ZSgpCiAgICAgICAgdGFpbCA9IChwcm9jIC8gJ3N0YXQnKS5yZWFkX3RleHQoKS5yc3BsaXQoJykgJywgMSlbMV0uc3BsaXQoKQogICAgICAgIHBhcmVudCwgdGlja3MgPSBpbnQodGFpbFsxXSksIGludCh0YWlsWzE5XSkKICAgICAgICBpZiBleGUgIT0gZXhlY3V0YWJsZSBvciBwYXJlbnQgIT0gb3MuZ2V0cGlkKCk6IHJldHVybiBOb25lCiAgICAgICAgcmV0dXJuIHN0cihleGUpLCBwYXJlbnQsIHRpY2tzCiAgICBleGNlcHQgKE9TRXJyb3IsIFZhbHVlRXJyb3IsIEluZGV4RXJyb3IpOgogICAgICAgIHJldHVybiBOb25lCgpkZWYgc25hcHNob3QoKToKICAgIHJlc3VsdCA9IHsnY2dyb3VwX2N1cnJlbnQnOiBtZW1vcnkoKSwgJ293bmVkX3BpZCc6IGNoaWxkLnBpZCBpZiBjaGlsZCBlbHNlIE5vbmV9CiAgICBpZiBjaGlsZDoKICAgICAgICB0cnk6CiAgICAgICAgICAgIHRhaWwgPSBQYXRoKCcvcHJvYycsIHN0cihjaGlsZC5waWQpLCAnc3RhdCcpLnJlYWRfdGV4dCgpLnJzcGxpdCgnKSAnLCAxKVsxXS5zcGxpdCgpCiAgICAgICAgICAgIHJlc3VsdFsncHJvY2Vzc19jcHVfc2Vjb25kcyddID0gKGludCh0YWlsWzExXSkgKyBpbnQodGFpbFsxMl0pKSAvIG9zLnN5c2NvbmYoJ1NDX0NMS19UQ0snKQogICAgICAgIGV4Y2VwdCAoT1NFcnJvciwgVmFsdWVFcnJvciwgSW5kZXhFcnJvcik6IHBhc3MKICAgIGlmIGNoaWxkOgogICAgICAgIHRyeToKICAgICAgICAgICAgdmFsdWVzID0gZGljdChsaW5lLnNwbGl0KCc6JywgMSkgZm9yIGxpbmUgaW4gUGF0aCgnL3Byb2MnLCBzdHIoY2hpbGQucGlkKSwgJ3N0YXR1cycpLnJlYWRfdGV4dCgpLnNwbGl0bGluZXMoKSBpZiAnOicgaW4gbGluZSkKICAgICAgICAgICAgZm9yIGtleSBpbiBbJ1ZtUlNTJywgJ1ZtSFdNJywgJ1ZtU2l6ZSddOgogICAgICAgICAgICAgICAgcmVzdWx0W2tleSArICdfa2liJ10gPSBpbnQodmFsdWVzLmdldChrZXksICcwIGtCJykuc3BsaXQoKVswXSkKICAgICAgICBleGNlcHQgKE9TRXJyb3IsIFZhbHVlRXJyb3IpOiBwYXNzCiAgICByZXR1cm4gcmVzdWx0CgpkZWYgc3RvcF9vd25lZChyZWFzb24pOgogICAgaWYgY2hpbGQgaXMgTm9uZSBvciBjaGlsZC5wb2xsKCkgaXMgbm90IE5vbmU6IHJldHVybgogICAgaWYgb3duZWRfaWRlbnRpdHkoKSAhPSBpZGVudGl0eSBvciBpZGVudGl0eSBpcyBOb25lOgogICAgICAgIGVtaXQoJ3NpZ25hbF9yZWZ1c2VkX2lkZW50aXR5X21pc21hdGNoJywgcmVhc29uPXJlYXNvbiwgb3duZWRfcGlkPWNoaWxkLnBpZCkKICAgICAgICByZXR1cm4KICAgIGVtaXQoJ3Rlcm1fb3duZWQnLCByZWFzb249cmVhc29uLCBpZGVudGl0eT1pZGVudGl0eSwgKipzbmFwc2hvdCgpKQogICAgY2hpbGQuc2VuZF9zaWduYWwoc2lnbmFsLlNJR1RFUk0pCiAgICBkZWFkbGluZSA9IHRpbWUubW9ub3RvbmljKCkgKyA1LjAKICAgIHdoaWxlIGNoaWxkLnBvbGwoKSBpcyBOb25lIGFuZCB0aW1lLm1vbm90b25pYygpIDwgZGVhZGxpbmU6IHRpbWUuc2xlZXAoLjA1KQogICAgaWYgY2hpbGQucG9sbCgpIGlzIE5vbmU6CiAgICAgICAgaWYgb3duZWRfaWRlbnRpdHkoKSA9PSBpZGVudGl0eToKICAgICAgICAgICAgZW1pdCgna2lsbF9vd25lZCcsIHJlYXNvbj1yZWFzb24sIGlkZW50aXR5PWlkZW50aXR5LCAqKnNuYXBzaG90KCkpCiAgICAgICAgICAgIGNoaWxkLmtpbGwoKQogICAgICAgIGVsc2U6IGVtaXQoJ2tpbGxfcmVmdXNlZF9pZGVudGl0eV9taXNtYXRjaCcsIHJlYXNvbj1yZWFzb24pCiAgICB0cnk6IGNoaWxkLndhaXQodGltZW91dD0yKQogICAgZXhjZXB0IHN1YnByb2Nlc3MuVGltZW91dEV4cGlyZWQ6IGVtaXQoJ293bmVkX2V4aXRfdW5jb25maXJtZWQnLCByZWFzb249cmVhc29uKQoKZGVmIGludGVycnVwdGVkKHNpZ251bSwgX2ZyYW1lKToKICAgIHN0b3Bfb3duZWQoJ3N1cGVydmlzb3Jfc2lnbmFsXycgKyBzdHIoc2lnbnVtKSkKICAgIHJhaXNlIFN5c3RlbUV4aXQoMTI4ICsgc2lnbnVtKQoKc2lnbmFsLnNpZ25hbChzaWduYWwuU0lHVEVSTSwgaW50ZXJydXB0ZWQpCnNpZ25hbC5zaWduYWwoc2lnbmFsLlNJR0lOVCwgaW50ZXJydXB0ZWQpCmJhc2VsaW5lID0gbWVtb3J5KCkKZW1pdCgnYmFzZWxpbmUnLCBjZ3JvdXBfY3VycmVudD1iYXNlbGluZSwgY2dyb3VwX2xpbWl0PXBoeXNpY2FsX2xpbWl0LCBlZmZlY3RpdmVfYnVkZ2V0PWxpbWl0LCBhZG1pc3Npb25fZXh0cmFfYnl0ZXM9YXJncy5hZG1pc3Npb25fZXh0cmFfbWliICogMTAyNCoqMiwgc3RvcF90aHJlc2hvbGQ9dGhyZXNob2xkLCByZXNlcnZlX2J5dGVzPWFyZ3MucmVzZXJ2ZV9taWIgKiAxMDI0KioyLCB0aW1lb3V0X3M9YXJncy50aW1lb3V0LCBleGVjdXRhYmxlPXN0cihleGVjdXRhYmxlKSkKaWYgYmFzZWxpbmUgKyBhcmdzLmFkbWlzc2lvbl9leHRyYV9taWIgKiAxMDI0KioyID49IHRocmVzaG9sZDoKICAgIGVtaXQoJ2FkbWlzc2lvbl9ibG9ja2VkX2hlYWRyb29tJyk7IHJhaXNlIFN5c3RlbUV4aXQoNzgpCnRyeToKICAgIGNoaWxkID0gc3VicHJvY2Vzcy5Qb3Blbihjb21tYW5kLCBzaGVsbD1GYWxzZSkKICAgIGlkZW50aXR5ID0gb3duZWRfaWRlbnRpdHkoKQogICAgaWYgaWRlbnRpdHkgaXMgTm9uZToKICAgICAgICAjIFBvcGVuIHN0YXJ0cyB0aGUgZXhhY3QgZXhlY3V0YWJsZSB3aXRob3V0IGEgc2hlbGwuIERvIG5vdCBzaWduYWwgYW55CiAgICAgICAgIyB1bnZlcmlmaWVkIFBJRDsgcmVwb3J0IHRoZSBhZG1pc3Npb24gZmFpbHVyZSByYXRoZXIgdGhhbiBndWVzc2luZy4KICAgICAgICBlbWl0KCdpZGVudGl0eV9ub3RfdmVyaWZpZWQnLCBvd25lZF9waWQ9Y2hpbGQucGlkKQogICAgICAgIHJhaXNlIFN5c3RlbUV4aXQoMikKICAgIGVtaXQoJ293bmVkX2xhdW5jaGVkJywgb3duZWRfcGlkPWNoaWxkLnBpZCwgaWRlbnRpdHk9aWRlbnRpdHkpCiAgICBuZXh0X2xvZyA9IDAuMAogICAgd2hpbGUgY2hpbGQucG9sbCgpIGlzIE5vbmU6CiAgICAgICAgZWxhcHNlZCA9IHRpbWUubW9ub3RvbmljKCkgLSBzdGFydAogICAgICAgIGN1cnJlbnQgPSBtZW1vcnkoKQogICAgICAgIGlmIGN1cnJlbnQgPj0gdGhyZXNob2xkOgogICAgICAgICAgICBlbWl0KCdtZW1vcnlfZ3VhcmRfdHJpZ2dlcmVkJywgKipzbmFwc2hvdCgpKQogICAgICAgICAgICBzdG9wX293bmVkKCdjZ3JvdXBfcmVzZXJ2ZScpOyBlbWl0KCdndWFyZF9jb21wbGV0ZScsIGNoaWxkX2V4aXQ9Y2hpbGQucG9sbCgpLCAqKnNuYXBzaG90KCkpOyByYWlzZSBTeXN0ZW1FeGl0KDc4KQogICAgICAgIGlmIGVsYXBzZWQgPj0gYXJncy50aW1lb3V0OgogICAgICAgICAgICBlbWl0KCdleHRlcm5hbF90aW1lb3V0JywgKipzbmFwc2hvdCgpKQogICAgICAgICAgICBzdG9wX293bmVkKCdleHRlcm5hbF90aW1lb3V0Jyk7IGVtaXQoJ3RpbWVvdXRfY29tcGxldGUnLCBjaGlsZF9leGl0PWNoaWxkLnBvbGwoKSwgKipzbmFwc2hvdCgpKTsgcmFpc2UgU3lzdGVtRXhpdCgxMjQpCiAgICAgICAgaWYgZWxhcHNlZCA+PSBuZXh0X2xvZzoKICAgICAgICAgICAgZW1pdCgnc2FtcGxlJywgKipzbmFwc2hvdCgpKTsgbmV4dF9sb2cgPSBlbGFwc2VkICsgLjI1CiAgICAgICAgdGltZS5zbGVlcCguMDUpCiAgICBjb2RlID0gY2hpbGQucmV0dXJuY29kZQogICAgZW1pdCgnZXhpdGVkJywgY2hpbGRfZXhpdD1jb2RlLCAqKnNuYXBzaG90KCkpCiAgICByYWlzZSBTeXN0ZW1FeGl0KGNvZGUgaWYgY29kZSA+PSAwIGVsc2UgMTI4IC0gY29kZSkKZmluYWxseToKICAgIGxvZy5mbHVzaCgpCg==')
SELECTION_ORIGINAL_SHA='12cb7487b1874e909013baaed105fb16759b852b9c36a5aa78e470b61445b69f'
OFFLINE_ORIGINAL_SHA='30ee6203c084cccc38169cd47d2f1fc109a96ee4ae8ad80132b0d744da15899a'
def digest(b): return hashlib.sha256(b).hexdigest()
def read(p):
    p=Path(p)
    if p.is_symlink() or not p.is_file(): raise ValueError('Expected regular file: '+str(p))
    return p.read_bytes()
def save(name,data):
    E.mkdir(parents=True,exist_ok=True)
    (E/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
def require(b,row):
    if len(b)!=row.get('size',row.get('bytes')) or digest(b)!=row['sha256']: raise ValueError('Pinned bytes mismatch')
def config():
    raw=read(PREFIX/'CANDIDATE_MANIFEST.json')
    if digest(raw)!=MANIFEST_SHA: raise ValueError('Candidate manifest changed')
    return json.loads(raw)
def source_pins():
    m=json.loads(read(ROOT/'updates/v29/manifest.json'))
    for row in m['files']: require(read(ROOT/row['path']),row)
    return {r['path']:digest(read(ROOT/r['path'])) for r in m['files']}
def run_restore(name,extra=()):
    with (E/(name+'.log')).open('w') as log:
        code=subprocess.call([sys.executable,'-B',str(ROOT/'tools/restore_repository.py'),*extra],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    if code: raise RuntimeError(name+' exited '+str(code))
    reports=[]
    for line in (E/(name+'.log')).read_text().splitlines():
        try:
            value=json.loads(line)
            if isinstance(value,dict) and 'source_files' in value:reports.append(value)
        except ValueError:pass
    if not reports:raise ValueError('Restorer final JSON report missing')
    print('DOT_QA_RESTORE',name,json.dumps(reports[-1]),flush=True)
    return reports[-1]
def install():
    E.mkdir(parents=True,exist_ok=True)
    c=config(); a=c['archive']; encoded=read(PREFIX/a['file'])
    require(encoded,{'size':a['encoded_bytes'],'sha256':a['encoded_sha256']})
    archive=base64.b64decode(encoded,validate=True)
    require(archive,{'size':a['zip_bytes'],'sha256':a['zip_sha256']})
    z=zipfile.ZipFile(io.BytesIO(archive)); names=z.namelist()
    if len(names)!=len(set(names)) or set(names)!=set(a['members']): raise ValueError('Exact archive member allowlist mismatch')
    payload={}
    for member in z.infolist():
        n=member.filename
        if member.is_dir() or stat.S_IFMT(member.external_attr>>16)!=stat.S_IFREG: raise ValueError('Non-regular archive member')
        if PurePosixPath(n).is_absolute() or '..' in PurePosixPath(n).parts or '\\' in n: raise ValueError('Unsafe member')
        b=z.read(n);require(b,a['members'][n]);payload[n]=b
    controls=json.loads(payload['updates/v29/manifest.json'])
    for name,row in controls['protected_public_files'].items(): require(read(ROOT/name),row)
    baseline_dist=read(ROOT/'distribution_manifest.json');baseline_wrap=read(ROOT/'tools/restore_repository.py')
    require(baseline_dist,controls['previous_distribution'])
    if digest(baseline_wrap)!=controls['release_wrapper']['before_sha256']:raise ValueError('Unknown base wrapper')
    (E/'original-distribution.json').write_bytes(baseline_dist);(E/'original-wrapper.py').write_bytes(baseline_wrap)
    for row in c['unchanged_validator_dependencies_included']:
        target=ROOT/row['path']
        if target.exists(): require(read(target),row)
    # All versioned controls and validator dependencies first; root distribution next; wrapper last.
    ordered=[n for n in names if n not in ('distribution_manifest.json','tools/restore_repository.py')]+['distribution_manifest.json','tools/restore_repository.py']
    for n in ordered:
        target=ROOT/n
        if target.is_symlink():raise ValueError('Control is symlink')
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(payload[n])
    final=run_restore('restore-final')
    source_pins();run_restore('check-final',('--check',))
    sm=json.loads(read(ROOT/'distribution_manifest.json'))['source_files']
    before={r['path']:(ROOT/r['path']).stat().st_mtime_ns for r in sm}
    repeat=run_restore('restore-repeat')
    if repeat.get('source_writes')!=0:raise ValueError('Authoritative repeat source writes are not zero')
    after={r['path']:(ROOT/r['path']).stat().st_mtime_ns for r in sm}
    if before!=after:raise ValueError('Repeated restoration changed source mtimes')
    p=source_pins();save('install-receipt.json',{'status':'restored_checked_repeat_zero_source_writes','environment':'dot native cloud Linux /workspace/wap','candidate_manifest_sha256':MANIFEST_SHA,'source_pins':p,'source_count':final['source_files'],'restore_report':final,'repeat_report':repeat,'guard_sha256':digest(GUARD_BYTES),'repository_default_restore_unchanged':True,'native_canonical_v28_unchanged':True})
    print('DOT_QA_INSTALL_PASS source_count',len(sm),'main',p['main.gd'],'repeat_zero_source_writes',flush=True)
def gate(kind):
    E.mkdir(parents=True,exist_ok=True);c=config();source_pins()
    work=E/(kind+'-'+time.strftime('%Y%m%dT%H%M%SZ',time.gmtime()))
    if work.exists():raise ValueError('Fresh gate directory required')
    work.mkdir(); guard=E/'guard_effective8g.py'
    if guard.exists() and read(guard)!=GUARD_BYTES:raise ValueError('Guard changed')
    guard.write_bytes(GUARD_BYTES)
    if kind=='selection':
        orig=ROOT/'candidates/selection-motion/9f74f93ffc1f/main-test-only/tests/selection_motion/test_main_events.gd'
        b=read(orig)
        if digest(b)!=SELECTION_ORIGINAL_SHA: raise ValueError('Original selection fixture changed')
        old=b'd759e33bbe942f9935a72cbf0d99495296259311bc0f221cb642b3a8ea85939a'
        if b.count(old)!=1:raise ValueError('Selection hash-binding seam changed')
        b=b.replace(old,MAIN_SHA.encode());test=work/'selection.gd';test.write_bytes(b)
        variable='SELECTION';result_marker='SELECTION_MAIN_EVENTS_RESULT';expected_checks=47
    elif kind=='offline':
        orig=ROOT/'candidates/offline-move-demo/b2bad55ceaf0/test-only/tests/offline_move_demo/test_main_flow.gd'
        b=read(orig)
        if digest(b)!=OFFLINE_ORIGINAL_SHA:raise ValueError('Original offline fixture changed')
        test=work/'offline.gd';test.write_bytes(b)
        variable='OFFLINE_MOVE';result_marker='OFFLINE_MOVE_MAIN_RESULT';expected_checks=33
    else:raise ValueError('Unknown gate')
    env=os.environ.copy()
    for axis in ('DATA','CACHE','CONFIG'):
        path=work/axis.lower();path.mkdir();env['XDG_'+axis+'_HOME']=str(path)
    user=work/'data/godot/app_userdata/雾岸纪事 · AI 沙盘'
    env['FOGBANK_'+variable+'_TEST_USER_DIR']=str(user)
    report=work/'report.json';env['FOGBANK_'+variable+'_TEST_REPORT']=str(report)
    command=[sys.executable,'-B',str(guard),'--log',str(work/'guard.jsonl'),'--timeout','180','--reserve-mib','512','--admission-extra-mib','1741','--','godot','--path',str(ROOT),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--script',str(test)]
    save(kind+'-request.json',{'source_pins':source_pins(),'fixture_original_sha256':digest(read(orig)),'fixture_executed_sha256':digest(b),'fixture_change':'selection Main binding only' if kind=='selection' else 'none','guard_sha256':digest(GUARD_BYTES),'expected_checks':expected_checks,'display':'native x11; synthetic real GUI events, no OS input or visual acceptance claim'})
    start=time.monotonic()
    with (work/'runtime.log').open('w') as log: code=subprocess.call(command,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    text=(work/'runtime.log').read_text(errors='replace')
    strict=[line for line in text.splitlines() if re.search(r'(?:SCRIPT ERROR:|ERROR:|WARNING:)',line)]
    result=json.loads(read(report)) if report.exists() else {}
    rows=[json.loads(line) for line in read(work/'guard.jsonl').decode().splitlines()] if (work/'guard.jsonl').exists() else []
    passed=code==0 and result.get('ok') is True and result.get('checks')==expected_checks and not strict and rows[-1]['event']=='exited' and rows[-1]['child_exit']==0
    summary={'status':'passed' if passed else 'failed','code':code,'elapsed_s':time.monotonic()-start,'checks':result.get('checks'),'failures':result.get('failures'),'strict_error_count':len(strict),'strict_errors':strict,'pid':result.get('pid'),'main_sha256':result.get('main_sha256'),'display':result.get('display_backend'),'last_guard_event':rows[-1] if rows else None,'environment':'dot native cloud Linux /workspace/wap','network_claim':'fixture records no provider work; no packet capture','receipt':result.get('receipt')}
    source_pins();save(kind+'-summary.json',summary);print('DOT_QA_GATE',kind,json.dumps(summary,ensure_ascii=False),flush=True)
    if not passed:raise SystemExit(1)
def import_assets():
    E.mkdir(parents=True,exist_ok=True);before=source_pins()
    work=E/('import-'+time.strftime('%Y%m%dT%H%M%SZ',time.gmtime()));work.mkdir()
    guard=E/'guard_effective8g.py'
    if guard.exists() and read(guard)!=GUARD_BYTES:raise ValueError('Guard changed')
    guard.write_bytes(GUARD_BYTES)
    command=[sys.executable,'-B',str(guard),'--log',str(work/'guard.jsonl'),'--timeout','180','--reserve-mib','512','--admission-extra-mib','1741','--','godot','--path',str(ROOT),'--headless','--editor','--import','--quit','--audio-driver','Dummy']
    with (work/'runtime.log').open('w') as log:code=subprocess.call(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    text=(work/'runtime.log').read_text(errors='replace');errors=[line for line in text.splitlines() if re.search(r'(?:SCRIPT ERROR:|ERROR:|WARNING:)',line)]
    after=source_pins()
    save('import-summary.json',{'code':code,'before':before,'after':after,'diagnostics':errors,'native_scope':'Official Godot editor asset import only; this is not a gameplay pass','log_directory':str(work)})
    print('DOT_QA_IMPORT',code,'diagnostic_lines',len(errors),'source9_unchanged',before==after,flush=True)
    if code or before!=after:raise SystemExit(1)
    run_restore('check-after-import',('--check',))
if __name__=='__main__':
    if len(sys.argv)!=2:raise SystemExit('Use install, selection, or offline')
    if sys.argv[1]=='install':install()
    elif sys.argv[1]=='import':import_assets()
    else:gate(sys.argv[1])
