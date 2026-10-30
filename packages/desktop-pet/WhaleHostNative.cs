using System;
using System.Text;
using System.Runtime.InteropServices;
namespace WhalePetHost {
  public static class NativeProcess {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr process,uint flags,StringBuilder name,ref int size);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateFile(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern uint GetFinalPathNameByHandle(IntPtr handle,StringBuilder path,uint size,uint flags);
    public static string PhysicalDirectory(string path) {
      string full=System.IO.Path.GetFullPath(path);
      IntPtr handle=CreateFile(full,0,7,IntPtr.Zero,3,0x02000000,IntPtr.Zero);
      if(handle==new IntPtr(-1))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      try {
        var result=new StringBuilder(32768);uint count=GetFinalPathNameByHandle(handle,result,(uint)result.Capacity,0);
        if(count==0 || count>=result.Capacity)throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        string value=result.ToString();
        if(value.StartsWith(@"\\?\UNC\",StringComparison.OrdinalIgnoreCase))return @"\\"+value.Substring(8);
        return value.StartsWith(@"\\?\",StringComparison.Ordinal)?value.Substring(4):value;
      }finally{CloseHandle(handle);}
    }
    public static string ImagePath(int pid) {
      IntPtr handle=OpenProcess(0x1000,false,pid);
      if(handle==IntPtr.Zero)return "";
      try {int size=32768;var name=new StringBuilder(size);return QueryFullProcessImageName(handle,0,name,ref size)?name.ToString():"";}
      finally {CloseHandle(handle);}
    }
  }
}
