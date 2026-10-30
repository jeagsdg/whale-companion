using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Diagnostics;
using System.Threading;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Web.Script.Serialization;

namespace WhalePetHost {
  public sealed class LifeState {
    public string[] hostKeys = new string[0];
    public bool enabled = true;
    public int attempts;
    public double retryAt;
    public double healthySince;
  }
  public static class Watch {
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength=1048576 };
    public static string Next(LifeState state,string[] hosts,bool enabled,bool stopped,bool healthy,double now) {
      var keys=hosts.Distinct().OrderBy(x=>x,StringComparer.Ordinal).Take(8).ToArray();
      bool opened=keys.Length>0 && (keys.Except(state.hostKeys).Any() || !state.enabled);
      state.hostKeys=keys;state.enabled=enabled;
      if(keys.Length==0 || !enabled){state.attempts=0;state.retryAt=0;state.healthySince=0;return "none";}
      if(opened){state.attempts=1;state.retryAt=now+15000;state.healthySince=0;return "wake";}
      if(stopped){state.healthySince=0;return "none";}
      if(healthy){if(state.healthySince==0)state.healthySince=now;if(now-state.healthySince>=30000){state.attempts=0;state.retryAt=0;}return "none";}
      state.healthySince=0;
      if(state.retryAt>now+120000)state.retryAt=now;
      if(state.attempts>=3 || now<state.retryAt)return "none";
      state.attempts++;state.retryAt=now+new double[]{15000,30000,120000}[state.attempts-1];return "recover";
    }
    static double Now(){return (DateTime.UtcNow-new DateTime(1970,1,1)).TotalMilliseconds;}
    static Dictionary<string,object> Read(string file) {
      try {
        if(new FileInfo(file).Length>1048576)return new Dictionary<string,object>();
        using(var stream=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
        using(var reader=new StreamReader(stream,Encoding.UTF8))return Json.Deserialize<Dictionary<string,object>>(reader.ReadToEnd()) ?? new Dictionary<string,object>();
      }catch{return new Dictionary<string,object>();}
    }
    static bool Flag(Dictionary<string,object> data,string key,bool fallback) {
      object value;bool result;return data.TryGetValue(key,out value) && bool.TryParse(Convert.ToString(value),out result)?result:fallback;
    }
    static string Text(Dictionary<string,object> data,string key){object value;return data.TryGetValue(key,out value)?Convert.ToString(value):"";}
    static void Save(string file,object value) {
      Directory.CreateDirectory(Path.GetDirectoryName(file));string temp=file+"."+Guid.NewGuid().ToString("N")+".tmp";
      try {
        File.WriteAllText(temp,Json.Serialize(value),new UTF8Encoding(false));
        for(int i=0;;i++){try{if(File.Exists(file))File.Replace(temp,file,null);else File.Move(temp,file);break;}catch{if(i>=3)throw;Thread.Sleep(15);}}
      }finally{if(File.Exists(temp))File.Delete(temp);}
    }
    static string MutexName(string role,string home) {
      using(var sha=SHA256.Create()){string hash=BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(Path.GetFullPath(home).TrimEnd('\\').ToLowerInvariant()))).Replace("-","").ToLowerInvariant();return "Local\\DshWhalePet."+role+"."+hash.Substring(0,24);}
    }
    static bool HasMutex(string name){try{using(Mutex.OpenExisting(name))return true;}catch{return false;}}
    static bool Healthy(string home,double now) {
      double stamp;var alive=Read(Path.Combine(home,"alive.json"));
      if(!double.TryParse(Text(alive,"at"),out stamp) || double.IsNaN(stamp) || double.IsInfinity(stamp) || stamp<=0 || now-stamp < -30000 || now-stamp>45000)return false;
      return HasMutex(MutexName("UI",home)) && HasMutex(MutexName("Codex",home)) && HasMutex("Local\\DshWhalePet.Bridge.19390");
    }
    public static string[] Hosts() {
      var keys=new List<string>();
      foreach(string name in new[]{"ChatGPT","Codex"})foreach(var process in Process.GetProcessesByName(name)) {
        try {
          if(process.MainWindowHandle==IntPtr.Zero)continue;
          string path=NativeProcess.ImagePath(process.Id);
          if(System.Text.RegularExpressions.Regex.IsMatch(path,@"(?i)\\WindowsApps\\OpenAI\.Codex_[^\\]+\\app\\(?:ChatGPT|Codex)\.exe$"))keys.Add("codex:"+process.Id+":"+process.StartTime.ToUniversalTime().Ticks);
        }catch{}finally{process.Dispose();}
      }
      return keys.ToArray();
    }
    static LifeState Load(string file) {
      try {
        var state=Json.Deserialize<LifeState>(Json.Serialize(Read(file))) ?? new LifeState();
        state.hostKeys=(state.hostKeys ?? new string[0]).Where(x=>x!=null && System.Text.RegularExpressions.Regex.IsMatch(x,@"^codex:[0-9]+:[0-9]+$")).Take(8).ToArray();
        state.attempts=Math.Max(0,Math.Min(3,state.attempts));
        if(double.IsNaN(state.retryAt) || double.IsInfinity(state.retryAt))state.retryAt=0;
        if(double.IsNaN(state.healthySince) || double.IsInfinity(state.healthySince))state.healthySince=0;
        return state;
      }catch{return new LifeState();}
    }
    static string Quote(string path){if(path.IndexOfAny(new[]{'"','\r','\n'})>=0)throw new ArgumentException("Invalid path");return "\""+path+"\"";}
    static void Launch(string home,string action) {
      var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),@"System32\WindowsPowerShell\v1.0\powershell.exe"));
      start.UseShellExecute=false;start.CreateNoWindow=true;start.WindowStyle=ProcessWindowStyle.Hidden;
      start.Arguments="-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "+Quote(Path.Combine(home,"whale-pet-start.ps1"))+" -PetHome "+Quote(home)+" -Auto"+(action=="wake"?" -HostOpen":"");
      using(var child=Process.Start(start)){} // Launcher owns its children; do not wait or open a host app.
    }
    [STAThread] public static int Main(string[] args) {
      string home=AppDomain.CurrentDomain.BaseDirectory;
      for(int i=0;i<args.Length;i++)if(args[i]=="--pet-home" && i+1<args.Length)home=args[++i];
      home=Path.GetFullPath(home);Directory.CreateDirectory(home);
      home=NativeProcess.PhysicalDirectory(home);
      bool created;using(var mutex=new Mutex(true,MutexName("HostWatch",home),out created)) {
        if(!created)return 0;
        string stateFile=Path.Combine(home,"host-lifecycle.json"),aliveFile=Path.Combine(home,"host-watch-alive.json"),log=Path.Combine(home,"host-watch.log");
        var state=Load(stateFile);double heartbeatAt=0,errorAt=0;string lastError="";int pid;
        using(var self=Process.GetCurrentProcess())pid=self.Id;
        try {
          while(true) {
            try {
              double now=Now();
              if(now-heartbeatAt>=10000){Save(aliveFile,new{pid=pid,at=now});heartbeatAt=now;}
              var prefs=Read(Path.Combine(home,"pet-preferences.json"));if(Text(prefs,"host")=="dsh")break;
              string before=Json.Serialize(state);
              var next=Json.Deserialize<LifeState>(before);
              string action=Next(next,Hosts(),Flag(prefs,"autoWakeOnHostStart",true),Flag(Read(Path.Combine(home,"control.json")),"stopped",false),Healthy(home,now),now);
              if(before!=Json.Serialize(next))Save(stateFile,next);
              state=next;
              if(action!="none")Launch(home,action);
            }catch(Exception error){
              double now=Now();
              if(error.Message!=lastError || now-errorAt>=60000){try{if(File.Exists(log) && new FileInfo(log).Length>65536)File.WriteAllText(log,"");File.AppendAllText(log,DateTime.Now.ToString("s")+" "+error.Message+Environment.NewLine);}catch{}lastError=error.Message;errorAt=now;}
            }
            Thread.Sleep(2000);
          }
        }finally{try{File.Delete(aliveFile);}catch{}mutex.ReleaseMutex();}
      }
      return 0;
    }
  }
}
