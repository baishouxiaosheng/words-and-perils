// Explicit owner invocation only; the ordinary wrapper never sets this mode.
public enum RunMode { Headless = 0, FocusedGui = 1 }
public sealed class OwnerFocusedGui {
 public string RunId, ExpectedGodotSha256;
}
public sealed class FocusedSource {
 public string Path, Sha256; public long Bytes;
 public FocusedSource(string path,long bytes,string sha) { Path=path; Bytes=bytes; Sha256=sha; }
}

// INSERT_IN_GUARD
 public static uint CreationFlags(RunMode mode) {
  if(mode!=RunMode.Headless && mode!=RunMode.FocusedGui) throw new ArgumentException("unknown_run_mode");
  return 0x4U|0x400U|0x80000U|BELOW_NORMAL|(mode==RunMode.Headless?0x08000000U:0U);
 }
 public static ushort ShowWindow(RunMode mode) {
  if(mode!=RunMode.Headless && mode!=RunMode.FocusedGui) throw new ArgumentException("unknown_run_mode");
  return (ushort)(mode==RunMode.Headless?0:1);
 }
 static string CanonicalOwnedPath(string path) {
  if(String.IsNullOrWhiteSpace(path) || !Path.IsPathRooted(path) || path.IndexOf('\0')>=0 || path.StartsWith(@"\\") || path.Substring(2).Contains(":") || String.Equals(path,Path.GetPathRoot(path),StringComparison.OrdinalIgnoreCase) || path.Split(Path.DirectorySeparatorChar).Any(part=>part.EndsWith(".")||part.EndsWith(" ")) || !String.Equals(path,Path.GetFullPath(path),StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("gui_canonical_local_path_required");
  string cursor=path;
  while(!String.IsNullOrEmpty(cursor)) {
   if((File.Exists(cursor)||Directory.Exists(cursor)) && (File.GetAttributes(cursor)&FileAttributes.ReparsePoint)!=0) throw new ArgumentException("gui_reparse_path");
   cursor=Path.GetDirectoryName(cursor);
  }
  return path.TrimEnd(Path.DirectorySeparatorChar);
 }
 static bool Under(string path,string parent) { return String.Equals(path,parent,StringComparison.OrdinalIgnoreCase) || path.StartsWith(parent+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase); }
 static bool ValidSha(string sha) { return sha!=null && sha.Length==64 && sha.All(c=>c>='0'&&c<='9'||c>='a'&&c<='f'); }
 static string Sha(Stream stream) {
  stream.Position=0; using(var hash=System.Security.Cryptography.SHA256.Create()) { return BitConverter.ToString(hash.ComputeHash(stream)).Replace("-","").ToLowerInvariant(); }
 }
 static readonly FocusedSource[] FocusedFiles = new FocusedSource[] {
// FIXED_SOURCE_MAP
 };
 static List<string> SourcePaths(string project) {
  var files=new List<string>(); var directories=new Stack<string>(); directories.Push(project);
  while(directories.Count!=0) {
   string directory=CanonicalOwnedPath(directories.Pop());
   foreach(string child in Directory.GetDirectories(directory)) directories.Push(child);
   foreach(string file in Directory.GetFiles(directory)) {
    CanonicalOwnedPath(file); string relative=file.Substring(project.Length+1).Replace('\\','/');
    // Godot-owned generated cache is isolated to this fixed fixture; never a source binding.
    if(!relative.StartsWith(".godot/",StringComparison.OrdinalIgnoreCase)) files.Add(relative);
   }
  }
  return files;
 }
 public sealed class GuiInputLease : IDisposable {
  internal string Project;
  readonly List<FileStream> leases=new List<FileStream>();
  internal void Bind(string path,long bytes,string sha) {
   var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read); leases.Add(file);
   if((bytes>=0 && file.Length!=bytes) || Sha(file)!=sha) throw new ArgumentException("gui_source_hash_mismatch");
  }
  public void VerifySourceSet() {
   var paths=SourcePaths(Project);
   if(paths.Count!=FocusedFiles.Length || !new HashSet<string>(paths,StringComparer.Ordinal).SetEquals(FocusedFiles.Select(f=>f.Path))) throw new ArgumentException("gui_source_closure_mismatch");
  }
  public void Dispose() {
   Exception error=null;
   foreach(var lease in leases) { try { lease.Dispose(); } catch(Exception ex) { if(error==null) error=ex; } }
   leases.Clear(); if(error!=null) throw new IOException("gui_input_lease_cleanup_failed",error);
  }
 }
 // Pure managed validation can be tested without calling any Win32 API or starting an engine.
 public static GuiInputLease ValidateFocusedGui(Options o) {
  if(o.Mode!=RunMode.FocusedGui || o.OwnerGui==null || String.IsNullOrWhiteSpace(o.OwnerGui.RunId) || o.OwnerGui.RunId.Length>128 || !o.OwnerGui.RunId.All(c=>Char.IsLetterOrDigit(c)||c=='-'||c=='_') || !ValidSha(o.OwnerGui.ExpectedGodotSha256)) throw new ArgumentException("explicit_owner_gui_binding_required");
  if(o.Profile!="small" || o.TimeoutSeconds!=120 || o.OutputLimitBytes!=MaximumOutputBytes || o.SelfTest || o.FaultMode!="none") throw new ArgumentException("gui_requires_small_production_limits");
  string exe=CanonicalOwnedPath(o.Executable), project=CanonicalOwnedPath(o.WorkingDirectory), data=CanonicalOwnedPath(o.IsolatedDataRoot);
  if(!String.Equals(Path.GetFileName(exe),"Godot_v4.6.3-stable_win64.exe",StringComparison.Ordinal) || !Directory.Exists(project) || !Directory.Exists(data) || Under(data,project) || Under(project,data) || Under(exe,project) || Under(exe,data)) throw new ArgumentException("gui_owned_roots_or_executable_invalid");
  var expected=new[]{"--path",project,"--script","res://tests/focused/local_gui.gd","--fixed-fps","15","--",data};
  if(o.Arguments==null || !o.Arguments.SequenceEqual(expected)) throw new ArgumentException("gui_arguments_not_exact_allowlist");
  var leaves=new[]{"appdata","localappdata","temp"};
  if(Directory.GetFiles(data).Length!=0 || Directory.GetDirectories(data).Length!=3 || leaves.Any(leaf=>!Directory.Exists(Path.Combine(data,leaf)) || Directory.GetFileSystemEntries(Path.Combine(data,leaf)).Length!=0)) throw new ArgumentException("gui_fresh_isolated_data_required");
  foreach(string leaf in leaves) CanonicalOwnedPath(Path.Combine(data,leaf));
  string cache=Path.Combine(project,".godot");
  if(Directory.Exists(cache) && Directory.GetFileSystemEntries(cache).Length!=0) throw new ArgumentException("gui_fresh_cache_required");
  var lease=new GuiInputLease { Project=project };
  try {
   lease.VerifySourceSet(); lease.Bind(exe,-1,o.OwnerGui.ExpectedGodotSha256);
   foreach(var file in FocusedFiles) lease.Bind(Path.Combine(project,file.Path.Replace('/',Path.DirectorySeparatorChar)),file.Bytes,file.Sha256);
   lease.VerifySourceSet(); return lease;
  } catch { lease.Dispose(); throw; }
 }
