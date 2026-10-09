using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace WordsAndPerils.NativeGuardV3 {
public sealed class MemoryReading { public bool Success; public ulong TotalPhysBytes, AvailPhysBytes; public int NativeError; }
public sealed class Admission {
 public bool Allowed; public string Reason; public ulong TotalPhysBytes, AvailPhysBytes, BudgetBytes, ReserveBytes, AdditionalBytes;
 public int ProfileTimeoutSeconds;
}
public sealed class Options {
 public string Executable, WorkingDirectory, IsolatedDataRoot;
 public string[] Arguments = new string[0];
 public string Profile = "small";
 public int TimeoutSeconds;
 public int OutputLimitBytes = 65536;
 public bool SelfTest;
 public string FaultMode = "none";
}
public sealed class OwnedProcess {
 public uint Pid; public string CreatedUtc; public bool JobMembershipVerified, Exited;
 internal IntPtr Handle;
}
public sealed class Sample {
 public double ElapsedSeconds; public bool NativeReadSuccess, EffectiveReadSuccess, Injected;
 public bool TerminalJobAndRootExited, DeadlineExceeded, DeadlineInjected;
 public ulong TotalPhysBytes, ActualAvailPhysBytes, EffectiveAvailPhysBytes, PeakJobCommitBytes;
 public uint[] JobPids;
}
public sealed class RunResult {
 public string Schema = "wordsandperils_windows_native_guard/v3";
 public string Status, StopReason, ErrorOperation, StartedUtc, EndedUtc, Stdout = "", Stderr = "";
 public bool Started, WorkloadResumed, JobAssignedBeforeResume, KillOnCloseVerified, BreakawayDisabledVerified;
 public bool JobEmptyAfterRun, AllRecordedHandlesExited, PhysicalMemoryWasActuallyRead, EnvironmentInherited = false;
 public bool SyntheticFault, EngineStarted;
 public bool OutputLimitExceeded, OutputLimitTerminationRequested, OutputLimitTerminationSucceeded, OutputReadersFinished;
 public int OutputLimitBytes, StdoutRetainedBytes, StderrRetainedBytes, OutputTerminationNativeError;
 public ulong OutputObservedBytes;
 public int NativeError, GuardExitCode, TimeoutSeconds;
 public uint RootPid, RootExitCode;
 public ulong JobCommitLimitBytes, QueriedJobCommitLimitBytes, PeakJobCommitBytes, LowestActualAvailPhysBytes, AffinityMask;
 public double ElapsedSeconds;
 public string MemoryScope = "Win32 physical availability independently; kernel job-wide committed-memory peak/limit includes descendants; guardian host outside job covered by reserve";
 public Admission Admission;
 public MemoryReading AdmissionNativeReading;
 public MemoryReading CompletionNativeReading;
 public bool CompletionDeadlineExceeded;
 public uint PriorityClassBeforeResume;
 public bool CreatedSuspended = true, NoWindowFlagRequested = true;
 public List<OwnedProcess> OwnedProcesses = new List<OwnedProcess>();
 public List<Sample> Samples = new List<Sample>();
}
public static class Guard {
 public const ulong MiB = 1024UL * 1024UL;
 public const ulong BudgetCapBytes = 8192UL * MiB, ReserveBytes = 512UL * MiB;
 public const int MaximumOutputBytes = 65536;
 const uint JOB_MEMORY = 0x200, KILL_ON_CLOSE = 0x2000, AFFINITY = 0x10, PRIORITY = 0x20;
 const uint BELOW_NORMAL = 0x4000, WAIT_TIMEOUT = 258;
 [StructLayout(LayoutKind.Sequential)] struct MEMORYSTATUSEX {
  public uint Length, Load; public ulong TotalPhys, AvailPhys, TotalPage, AvailPage, TotalVirtual, AvailVirtual, AvailExtended;
 }
 [StructLayout(LayoutKind.Sequential)] struct BASIC_LIMIT {
  public long ProcessTime, JobTime; public uint Flags; public UIntPtr MinWorkingSet, MaxWorkingSet;
  public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass, SchedulingClass;
 }
 [StructLayout(LayoutKind.Sequential)] struct IO_COUNTERS { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
 [StructLayout(LayoutKind.Sequential)] struct EXTENDED_LIMIT {
  public BASIC_LIMIT Basic; public IO_COUNTERS Io; public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
 }
 [StructLayout(LayoutKind.Sequential)] struct SECURITY_ATTRIBUTES { public int Length; public IntPtr Descriptor; [MarshalAs(UnmanagedType.Bool)] public bool Inherit; }
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct STARTUPINFO {
  public int cb; public string Reserved, Desktop, Title; public uint X, Y, XSize, YSize, XChars, YChars, Fill, Flags;
  public ushort ShowWindow, Reserved2; public IntPtr ReservedBytes, StdInput, StdOutput, StdError;
 }
 [StructLayout(LayoutKind.Sequential)] struct STARTUPINFOEX { public STARTUPINFO Info; public IntPtr Attributes; }
 [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr Process, Thread; public uint Pid, Tid; }
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX s);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attrs, string name);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr j, int cls, ref EXTENDED_LIMIT info, uint length);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr j, int cls, IntPtr info, uint length, out uint returned);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool IsProcessInJob(IntPtr p, IntPtr j, out bool inside);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr j, uint code);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateProcess(IntPtr p, uint code);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr t);
 [DllImport("kernel32.dll", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr p, out uint code);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessTimes(IntPtr p, out long c, out long e, out long k, out long u);
 [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessAffinityMask(IntPtr p, out UIntPtr process, out UIntPtr system);
 [DllImport("kernel32.dll", SetLastError=true)] static extern uint GetPriorityClass(IntPtr p);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool CreatePipe(out IntPtr read, out IntPtr write, ref SECURITY_ATTRIBUTES attrs, uint size);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetHandleInformation(IntPtr h, uint mask, uint flags);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr bytes);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr key, IntPtr value, IntPtr size, IntPtr old, IntPtr returned);
 [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcessW(string app, StringBuilder command, IntPtr processAttrs, IntPtr threadAttrs, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFOEX start, out PROCESS_INFORMATION info);

 public static MemoryReading ReadPhysicalMemory() {
  var s = new MEMORYSTATUSEX(); s.Length = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
  bool okay = GlobalMemoryStatusEx(ref s);
  return new MemoryReading { Success=okay && s.TotalPhys>0 && s.AvailPhys<=s.TotalPhys, TotalPhysBytes=s.TotalPhys, AvailPhysBytes=s.AvailPhys, NativeError=okay?0:Marshal.GetLastWin32Error() };
 }
 public static Admission Evaluate(bool readable, ulong total, ulong available, string profile) {
  var a = new Admission { TotalPhysBytes=total, AvailPhysBytes=available, BudgetBytes=Math.Min(total,BudgetCapBytes), ReserveBytes=ReserveBytes };
  if(profile=="small") { a.AdditionalBytes=1024UL*MiB; a.ProfileTimeoutSeconds=120; }
  else if(profile=="full") { a.AdditionalBytes=1741UL*MiB; a.ProfileTimeoutSeconds=180; }
  else { a.Reason="unknown_profile"; return a; }
  if(!readable || total==0 || available>total) a.Reason="physical_sensor_unreadable_or_invalid";
  else if(a.BudgetBytes < a.AdditionalBytes+a.ReserveBytes) a.Reason="task_budget_insufficient";
  else if(available < a.AdditionalBytes+a.ReserveBytes) a.Reason="physical_admission_insufficient";
  else { a.Allowed=true; a.Reason="admitted"; }
  return a;
 }
 static void Need(bool value, string operation) { if(!value) throw new NativeFailure(operation,Marshal.GetLastWin32Error()); }
 sealed class NativeFailure : Exception { public string Operation; public int Code; public NativeFailure(string op,int code):base(op) { Operation=op; Code=code; } }
 static EXTENDED_LIMIT ReadLimits(IntPtr job) {
  int size=Marshal.SizeOf(typeof(EXTENDED_LIMIT)); IntPtr p=Marshal.AllocHGlobal(size);
  try { uint returned; Need(QueryInformationJobObject(job,9,p,(uint)size,out returned),"query_job_limits"); return (EXTENDED_LIMIT)Marshal.PtrToStructure(p,typeof(EXTENDED_LIMIT)); }
  finally { Marshal.FreeHGlobal(p); }
 }
 static uint[] Pids(IntPtr job) {
  int capacity=32;
  while(capacity<=4096) {
   int size=8+capacity*IntPtr.Size; IntPtr p=Marshal.AllocHGlobal(size);
   try { uint returned; if(QueryInformationJobObject(job,3,p,(uint)size,out returned)) {
    int count=Marshal.ReadInt32(p,4); if(count<0 || count>capacity) throw new NativeFailure("invalid_job_pid_count",0);
    var ids=new uint[count]; for(int i=0;i<count;i++) ids[i]=(uint)(IntPtr.Size==8?Marshal.ReadInt64(p,8+i*IntPtr.Size):Marshal.ReadInt32(p,8+i*IntPtr.Size)); return ids;
   } if(Marshal.GetLastWin32Error()!=234) throw new NativeFailure("query_job_pids",Marshal.GetLastWin32Error()); }
   finally { Marshal.FreeHGlobal(p); }
   capacity*=2;
  }
  throw new NativeFailure("job_pid_capacity_exceeded",0);
 }
 static void Track(IntPtr job, uint[] ids, RunResult r) {
  foreach(uint pid in ids) {
   if(r.OwnedProcesses.Any(x=>x.Pid==pid)) continue;
   IntPtr h=OpenProcess(0x1000|0x100000,false,pid);
   if(h==IntPtr.Zero) { if(!Pids(job).Contains(pid)) continue; throw new NativeFailure("open_owned_job_member",Marshal.GetLastWin32Error()); }
   bool keep=false;
   try { bool inside; Need(IsProcessInJob(h,job,out inside),"verify_child_job_membership"); if(!inside) throw new NativeFailure("child_identity_job_mismatch",0);
    long c,e,k,u; Need(GetProcessTimes(h,out c,out e,out k,out u),"read_owned_creation_time");
    r.OwnedProcesses.Add(new OwnedProcess { Pid=pid, CreatedUtc=DateTime.FromFileTimeUtc(c).ToString("o"), JobMembershipVerified=true, Handle=h }); keep=true;
   } finally { if(!keep) CloseHandle(h); }
  }
 }
 static string Quote(string value) {
  if(value==null || value.IndexOf('\0')>=0) throw new ArgumentException("invalid_argument");
  var b=new StringBuilder("\""); int slashes=0;
  foreach(char c in value) { if(c=='\\') { slashes++; continue; } if(c=='\"') { b.Append('\\',slashes*2+1); b.Append(c); } else { b.Append('\\',slashes); b.Append(c); } slashes=0; }
  b.Append('\\',slashes*2); b.Append('"'); return b.ToString();
 }
 public static Dictionary<string,string> ChildEnvironment(string dataRoot) {
  if(String.IsNullOrWhiteSpace(dataRoot) || !Path.IsPathRooted(dataRoot)) throw new ArgumentException("absolute_isolated_data_root_required");
  string root=Path.GetFullPath(dataRoot), windows=Environment.GetFolderPath(Environment.SpecialFolder.Windows);
  foreach(string leaf in new[]{"appdata","localappdata","temp"}) {
   string cursor=Path.Combine(root,leaf);
   while(!String.IsNullOrEmpty(cursor)) { if(Directory.Exists(cursor) || File.Exists(cursor)) { if((File.GetAttributes(cursor)&FileAttributes.ReparsePoint)!=0) throw new ArgumentException("reparse_isolation_path"); } cursor=Path.GetDirectoryName(cursor); }
  }
  return new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase) {
   {"SystemRoot",windows},{"WINDIR",windows},{"COMSPEC",Path.Combine(windows,"System32","cmd.exe")},
   {"PATH",Path.Combine(windows,"System32")}, {"APPDATA",Path.Combine(root,"appdata")},
   {"LOCALAPPDATA",Path.Combine(root,"localappdata")},{"TEMP",Path.Combine(root,"temp")},{"TMP",Path.Combine(root,"temp")}
  };
 }
 static IntPtr EnvironmentBlock(Dictionary<string,string> values) {
  string text=String.Join("\0",values.OrderBy(x=>x.Key,StringComparer.OrdinalIgnoreCase).Select(x=>x.Key+"="+x.Value))+"\0\0";
  return Marshal.StringToHGlobalUni(text);
 }
 sealed class OutputCapture {
  readonly object dataGate = new object(), jobGate = new object();
  readonly byte[] outBytes, errBytes;
  readonly int limit;
  int outCount, errCount, nativeError;
  ulong observed;
  IntPtr ownedJob;
  bool terminationRequested, terminationSucceeded;
  public volatile bool LimitExceeded, ReaderFailed;
  public OutputCapture(int bytes) { limit=bytes; outBytes=new byte[bytes]; errBytes=new byte[bytes]; }
  public void AttachJob(IntPtr job) { lock(jobGate) ownedJob=job; }
  public void DetachJob() { lock(jobGate) ownedJob=IntPtr.Zero; }
  void StopOnlyOwnedJob(uint code) {
   lock(jobGate) {
    if(ownedJob==IntPtr.Zero) return;
    terminationRequested=true;
    terminationSucceeded=TerminateJobObject(ownedJob,code);
    if(!terminationSucceeded) nativeError=Marshal.GetLastWin32Error();
   }
  }
  public bool Append(bool error, byte[] bytes, int count) {
   bool overflow;
   lock(dataGate) {
    observed+=(ulong)count;
    int remaining=limit-outCount-errCount, keep=Math.Min(count,remaining);
    if(keep>0) {
     Buffer.BlockCopy(bytes,0,error?errBytes:outBytes,error?errCount:outCount,keep);
     if(error) errCount+=keep; else outCount+=keep;
    }
    overflow=count>remaining;
    if(overflow) LimitExceeded=true;
   }
   if(overflow) StopOnlyOwnedJob(128);
   return !overflow;
  }
  public void FailReader() { ReaderFailed=true; StopOnlyOwnedJob(131); }
  public void Report(RunResult r) {
   lock(dataGate) {
    r.OutputLimitBytes=limit; r.OutputObservedBytes=observed;
    r.StdoutRetainedBytes=outCount; r.StderrRetainedBytes=errCount;
    r.Stdout=Encoding.UTF8.GetString(outBytes,0,outCount);
    r.Stderr=Encoding.UTF8.GetString(errBytes,0,errCount);
    r.OutputLimitExceeded=LimitExceeded;
   }
   lock(jobGate) {
    r.OutputLimitTerminationRequested=terminationRequested;
    r.OutputLimitTerminationSucceeded=terminationSucceeded;
    r.OutputTerminationNativeError=nativeError;
   }
  }
 }
 static Task Reader(ref IntPtr handle, OutputCapture output, bool error) {
  var safe=new SafeFileHandle(handle,true); handle=IntPtr.Zero;
  var stream=new FileStream(safe,FileAccess.Read,4096,false);
  return Task.Run(()=> {
   try { using(stream) { var buffer=new byte[4096]; int count;
    while((count=stream.Read(buffer,0,buffer.Length))>0) if(!output.Append(error,buffer,count)) break;
   } } catch { output.FailReader(); }
  });
 }
 static void Close(ref IntPtr h) { if(h!=IntPtr.Zero) { CloseHandle(h); h=IntPtr.Zero; } }

 public static RunResult Run(Options o) {
  var r=new RunResult { Status="refused", StartedUtc=DateTime.UtcNow.ToString("o"), SyntheticFault=o.FaultMode!="none" };
  var watch=Stopwatch.StartNew(); IntPtr job=IntPtr.Zero, attributes=IntPtr.Zero, handles=IntPtr.Zero, environment=IntPtr.Zero;
  IntPtr outRead=IntPtr.Zero,outWrite=IntPtr.Zero,errRead=IntPtr.Zero,errWrite=IntPtr.Zero,inRead=IntPtr.Zero,inWrite=IntPtr.Zero;
  bool attributesReady=false; PROCESS_INFORMATION pi=new PROCESS_INFORMATION(); Task stdout=null,stderr=null; OutputCapture output=null;
  try {
   if(o.FaultMode!="none" && !o.SelfTest) throw new ArgumentException("fault_injection_requires_explicit_selftest");
   if(!new[]{"none","admission_unreadable","admission_low","monitor_unreadable","monitor_low","cleanup_close_job","terminal_unreadable","terminal_low","terminal_deadline","terminal_reader_failure"}.Contains(o.FaultMode)) throw new ArgumentException("unknown_fault_mode");
   if(o.OutputLimitBytes<128 || o.OutputLimitBytes>MaximumOutputBytes || (!o.SelfTest && o.OutputLimitBytes!=MaximumOutputBytes)) throw new ArgumentException("output_limit_requires_64KiB_or_smaller_explicit_selftest");
   r.OutputLimitBytes=o.OutputLimitBytes;
   var first=ReadPhysicalMemory(); r.AdmissionNativeReading=first; r.PhysicalMemoryWasActuallyRead=first.Success;
   bool readable=first.Success && o.FaultMode!="admission_unreadable";
   ulong available=o.FaultMode=="admission_low"?ReserveBytes-1:first.AvailPhysBytes;
   r.Admission=Evaluate(readable,first.TotalPhysBytes,available,o.Profile);
   if(!r.Admission.Allowed) { r.StopReason=r.Admission.Reason; r.GuardExitCode=2; return r; }
   r.TimeoutSeconds=o.TimeoutSeconds==0?r.Admission.ProfileTimeoutSeconds:o.TimeoutSeconds;
   if(r.TimeoutSeconds<1 || r.TimeoutSeconds>r.Admission.ProfileTimeoutSeconds) throw new ArgumentException("timeout_outside_profile");
   if(!Path.IsPathRooted(o.Executable) || !File.Exists(o.Executable) || !Directory.Exists(o.WorkingDirectory)) throw new ArgumentException("absolute_executable_and_existing_working_directory_required");
   bool isGodot=Path.GetFileName(o.Executable).IndexOf("godot",StringComparison.OrdinalIgnoreCase)>=0;
   if(isGodot && !o.Arguments.Contains("--headless")) throw new ArgumentException("godot_requires_explicit_headless");
   r.JobCommitLimitBytes=r.Admission.AdditionalBytes; r.LowestActualAvailPhysBytes=first.AvailPhysBytes;
   var env=ChildEnvironment(o.IsolatedDataRoot); environment=EnvironmentBlock(env);
   job=CreateJobObject(IntPtr.Zero,null); Need(job!=IntPtr.Zero,"create_private_job");
   output=new OutputCapture(o.OutputLimitBytes); output.AttachJob(job);
   UIntPtr allowed,system; Need(GetProcessAffinityMask(Process.GetCurrentProcess().Handle,out allowed,out system),"read_own_affinity");
   ulong mask=0, raw=allowed.ToUInt64(); int selected=0;
   for(int bit=0;bit<64 && selected<2;bit++) { ulong b=1UL<<bit; if((raw&b)!=0) { mask|=b; selected++; } }
   if(selected==0) throw new NativeFailure("no_allowed_cpu",0); r.AffinityMask=mask;
   var limit=new EXTENDED_LIMIT(); limit.Basic.Flags=JOB_MEMORY|KILL_ON_CLOSE|AFFINITY|PRIORITY;
   limit.Basic.Affinity=new UIntPtr(mask); limit.Basic.PriorityClass=BELOW_NORMAL; limit.JobMemory=new UIntPtr(r.JobCommitLimitBytes);
   Need(SetInformationJobObject(job,9,ref limit,(uint)Marshal.SizeOf(typeof(EXTENDED_LIMIT))),"set_private_job_limits");
   var actual=ReadLimits(job); r.QueriedJobCommitLimitBytes=actual.JobMemory.ToUInt64();
   r.KillOnCloseVerified=(actual.Basic.Flags&KILL_ON_CLOSE)!=0; r.BreakawayDisabledVerified=(actual.Basic.Flags&(0x800|0x1000))==0;
   if(r.QueriedJobCommitLimitBytes!=r.JobCommitLimitBytes || !r.KillOnCloseVerified || !r.BreakawayDisabledVerified || actual.Basic.Affinity.ToUInt64()!=mask || actual.Basic.PriorityClass!=BELOW_NORMAL) throw new NativeFailure("job_limits_readback_mismatch",0);
   var sa=new SECURITY_ATTRIBUTES { Length=Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)), Inherit=true };
   Need(CreatePipe(out outRead,out outWrite,ref sa,0),"create_stdout_pipe"); Need(SetHandleInformation(outRead,1,0),"restrict_stdout_read");
   Need(CreatePipe(out errRead,out errWrite,ref sa,0),"create_stderr_pipe"); Need(SetHandleInformation(errRead,1,0),"restrict_stderr_read");
   Need(CreatePipe(out inRead,out inWrite,ref sa,0),"create_stdin_pipe"); Need(SetHandleInformation(inWrite,1,0),"restrict_stdin_write"); Close(ref inWrite);
   IntPtr attributeBytes=IntPtr.Zero; InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref attributeBytes);
   if(attributeBytes==IntPtr.Zero) throw new NativeFailure("size_attribute_list",Marshal.GetLastWin32Error());
   attributes=Marshal.AllocHGlobal(attributeBytes); Need(InitializeProcThreadAttributeList(attributes,1,0,ref attributeBytes),"initialize_handle_attributes"); attributesReady=true;
   handles=Marshal.AllocHGlobal(IntPtr.Size*3); Marshal.WriteIntPtr(handles,0,outWrite); Marshal.WriteIntPtr(handles,IntPtr.Size,errWrite); Marshal.WriteIntPtr(handles,IntPtr.Size*2,inRead);
   Need(UpdateProcThreadAttribute(attributes,0,new IntPtr(0x20002),handles,new IntPtr(IntPtr.Size*3),IntPtr.Zero,IntPtr.Zero),"restrict_inherited_handles");
   var start=new STARTUPINFOEX(); start.Info.cb=Marshal.SizeOf(typeof(STARTUPINFOEX)); start.Info.Flags=0x100|1; start.Info.ShowWindow=0;
   start.Info.StdInput=inRead; start.Info.StdOutput=outWrite; start.Info.StdError=errWrite; start.Attributes=attributes;
   var command=new StringBuilder(Quote(o.Executable)); foreach(string arg in o.Arguments) command.Append(' ').Append(Quote(arg));
   Need(CreateProcessW(o.Executable,command,IntPtr.Zero,IntPtr.Zero,true,0x4|0x08000000|0x400|0x80000|BELOW_NORMAL,environment,o.WorkingDirectory,ref start,out pi),"create_suspended_owned_process");
   r.Started=true; r.RootPid=pi.Pid;
   Need(AssignProcessToJobObject(job,pi.Process),"assign_before_resume"); bool inside; Need(IsProcessInJob(pi.Process,job,out inside),"verify_root_job");
   if(!inside) throw new NativeFailure("root_not_in_private_job",0); r.JobAssignedBeforeResume=true;
   long created,ended,kernel,user; Need(GetProcessTimes(pi.Process,out created,out ended,out kernel,out user),"root_creation_time");
   r.OwnedProcesses.Add(new OwnedProcess { Pid=pi.Pid,CreatedUtc=DateTime.FromFileTimeUtc(created).ToString("o"),JobMembershipVerified=true,Handle=pi.Process });
   r.PriorityClassBeforeResume=GetPriorityClass(pi.Process);
   if(r.PriorityClassBeforeResume!=BELOW_NORMAL) throw new NativeFailure("root_priority_mismatch",0);
   Close(ref outWrite); Close(ref errWrite); Close(ref inRead); stdout=Reader(ref outRead,output,false); stderr=Reader(ref errRead,output,true);
   uint resumed=ResumeThread(pi.Thread); if(resumed!=1) throw new NativeFailure("resume_owned_thread",Marshal.GetLastWin32Error()); r.WorkloadResumed=true; Close(ref pi.Thread);
   r.EngineStarted=isGodot && r.WorkloadResumed;
   r.Status="running";
   while(true) {
    uint[] ids=Pids(job); Track(job,ids,r); var limits=ReadLimits(job);
    r.PeakJobCommitBytes=Math.Max(r.PeakJobCommitBytes,limits.PeakJobMemory.ToUInt64());
    bool terminal=ids.Length==0 && WaitForSingleObject(pi.Process,0)==0;
    bool runtimeInjection=r.Samples.Count>=2 && (o.FaultMode=="monitor_unreadable" || o.FaultMode=="monitor_low");
    bool terminalInjection=terminal && o.FaultMode.StartsWith("terminal_",StringComparison.Ordinal);
    var mem=ReadPhysicalMemory(); bool injected=runtimeInjection || terminalInjection;
    bool valid=mem.Success && !(runtimeInjection && o.FaultMode=="monitor_unreadable") && !(terminalInjection && o.FaultMode=="terminal_unreadable");
    ulong effectiveAvail=(runtimeInjection && o.FaultMode=="monitor_low") || (terminalInjection && o.FaultMode=="terminal_low")?ReserveBytes-1:mem.AvailPhysBytes;
    bool deadlineInjected=terminalInjection && o.FaultMode=="terminal_deadline";
    bool deadlineExceeded=watch.Elapsed.TotalSeconds>=r.TimeoutSeconds || deadlineInjected;
    if(terminalInjection && o.FaultMode=="terminal_reader_failure") output.FailReader();
    if(mem.Success) r.LowestActualAvailPhysBytes=Math.Min(r.LowestActualAvailPhysBytes,mem.AvailPhysBytes);
    r.Samples.Add(new Sample { ElapsedSeconds=Math.Round(watch.Elapsed.TotalSeconds,4),NativeReadSuccess=mem.Success,EffectiveReadSuccess=valid,Injected=injected,TerminalJobAndRootExited=terminal,DeadlineExceeded=deadlineExceeded,DeadlineInjected=deadlineInjected,TotalPhysBytes=mem.TotalPhysBytes,ActualAvailPhysBytes=mem.AvailPhysBytes,EffectiveAvailPhysBytes=effectiveAvail,PeakJobCommitBytes=r.PeakJobCommitBytes,JobPids=ids });
    if(output.LimitExceeded) { r.StopReason="output_limit_exceeded"; r.GuardExitCode=128; }
    else if(output.ReaderFailed) { r.StopReason="output_reader_failed"; r.GuardExitCode=131; }
    else if(!valid) { r.StopReason="physical_monitor_unreadable"; r.GuardExitCode=125; }
    else if(effectiveAvail<ReserveBytes) { r.StopReason="physical_reserve_below_512_MiB"; r.GuardExitCode=126; }
    else if(Math.Min(mem.TotalPhysBytes,BudgetCapBytes)<ReserveBytes+r.JobCommitLimitBytes) { r.StopReason="physical_total_budget_shrank"; r.GuardExitCode=126; }
    else if(r.PeakJobCommitBytes>r.JobCommitLimitBytes) { r.StopReason="job_commit_limit_violation"; r.GuardExitCode=126; }
    else if(deadlineExceeded) { r.StopReason="wall_clock_timeout"; r.GuardExitCode=124; }
    else if(o.FaultMode=="cleanup_close_job" && r.Samples.Count>=3) { r.StopReason="selftest_close_private_job"; r.GuardExitCode=127; }
    if(r.StopReason!=null) {
     Track(job,Pids(job),r); r.Status="stopped";
     if(o.FaultMode=="cleanup_close_job") { output.DetachJob(); Close(ref job); }
     else Need(TerminateJobObject(job,(uint)r.GuardExitCode),"terminate_only_private_job");
     break;
    }
    if(terminal) { r.Status="completed"; r.GuardExitCode=0; break; }
    Thread.Sleep(100);
   }
   var cleanup=Stopwatch.StartNew();
   while(cleanup.Elapsed.TotalSeconds<5) { bool exited=r.OwnedProcesses.All(x=>WaitForSingleObject(x.Handle,0)==0); bool empty=job==IntPtr.Zero || Pids(job).Length==0; if(exited && empty) break; Thread.Sleep(50); }
   foreach(var p in r.OwnedProcesses) p.Exited=WaitForSingleObject(p.Handle,0)==0;
   r.AllRecordedHandlesExited=r.OwnedProcesses.All(x=>x.Exited); r.JobEmptyAfterRun=job==IntPtr.Zero?r.AllRecordedHandlesExited:Pids(job).Length==0;
   if(!r.AllRecordedHandlesExited || !r.JobEmptyAfterRun) throw new NativeFailure("owned_cleanup_incomplete",0);
   Need(GetExitCodeProcess(pi.Process,out r.RootExitCode),"read_owned_exit_code");
   if(stdout!=null && stderr!=null) { if(!Task.WaitAll(new Task[]{stdout,stderr},5000)) throw new NativeFailure("owned_pipe_cleanup_timeout",0); r.OutputReadersFinished=true; output.Report(r); }
   if(output.LimitExceeded) { r.Status="stopped"; r.StopReason="output_limit_exceeded"; r.GuardExitCode=128; }
   else if(output.ReaderFailed) { r.Status="failed"; r.StopReason="output_reader_failed"; r.GuardExitCode=131; }
   if(r.Status=="completed") {
    var finalMemory=ReadPhysicalMemory();
    r.CompletionNativeReading=finalMemory; r.CompletionDeadlineExceeded=watch.Elapsed.TotalSeconds>=r.TimeoutSeconds;
    if(!finalMemory.Success) { r.Status="stopped"; r.StopReason="physical_monitor_unreadable"; r.GuardExitCode=125; }
    else if(finalMemory.AvailPhysBytes<ReserveBytes || Math.Min(finalMemory.TotalPhysBytes,BudgetCapBytes)<ReserveBytes+r.JobCommitLimitBytes) { r.Status="stopped"; r.StopReason="physical_reserve_or_budget_insufficient_at_completion"; r.GuardExitCode=126; }
    else if(r.CompletionDeadlineExceeded) { r.Status="stopped"; r.StopReason="wall_clock_timeout"; r.GuardExitCode=124; }
   }
   if(r.Status=="completed" && r.RootExitCode!=0) { r.Status="workload_failed"; r.GuardExitCode=1; }
  } catch(NativeFailure ex) { r.Status="failed"; r.ErrorOperation=ex.Operation; r.NativeError=ex.Code; r.GuardExitCode=3; }
    catch(Exception ex) { r.Status="failed"; r.ErrorOperation=ex.GetType().Name+": "+ex.Message; r.GuardExitCode=3; }
  finally {
   if(pi.Process!=IntPtr.Zero && WaitForSingleObject(pi.Process,0)==WAIT_TIMEOUT) {
    if(r.JobAssignedBeforeResume && job!=IntPtr.Zero) TerminateJobObject(job,129);
    else if(!r.JobAssignedBeforeResume) TerminateProcess(pi.Process,129);
    WaitForSingleObject(pi.Process,5000);
   }
   if(output!=null) output.DetachJob(); Close(ref job);
   foreach(var p in r.OwnedProcesses) if(p.Handle!=pi.Process) { p.Exited=WaitForSingleObject(p.Handle,0)==0; CloseHandle(p.Handle); p.Handle=IntPtr.Zero; }
   if(pi.Process!=IntPtr.Zero) { WaitForSingleObject(pi.Process,5000); Close(ref pi.Process); } Close(ref pi.Thread);
   Close(ref outRead); Close(ref outWrite); Close(ref errRead); Close(ref errWrite); Close(ref inRead); Close(ref inWrite);
   if(stdout!=null && stderr!=null) { r.OutputReadersFinished=Task.WaitAll(new Task[]{stdout,stderr},5000); }
   if(output!=null) output.Report(r);
   if(attributesReady) DeleteProcThreadAttributeList(attributes); if(attributes!=IntPtr.Zero) Marshal.FreeHGlobal(attributes); if(handles!=IntPtr.Zero) Marshal.FreeHGlobal(handles); if(environment!=IntPtr.Zero) Marshal.FreeHGlobal(environment);
   r.ElapsedSeconds=Math.Round(watch.Elapsed.TotalSeconds,4); r.EndedUtc=DateTime.UtcNow.ToString("o");
  }
  return r;
 }
}
}
