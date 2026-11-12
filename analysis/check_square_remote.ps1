param([Parameter(Mandatory=$true)][string]$RobotAddress)
# Integration check sends AUTH, HEARTBEAT and STOP only. Never sends START.
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$key=[IO.File]::ReadAllText((Join-Path $taskRoot 'robot-programs\DigitalTwin_LPath\robot-control.key')).Trim()
if($key -notmatch '^[0-9a-f]{32}$'){throw 'Invalid private control key'}
$script:received=[Collections.Generic.List[string]]::new()
function Read-MatchingLine($reader,[string]$pattern,[int]$seconds){
    $until=[DateTime]::UtcNow.AddSeconds($seconds)
    while([DateTime]::UtcNow -lt $until){
        try{$line=$reader.ReadLine()}catch [IO.IOException]{continue}
        if($null -eq $line){throw 'Robot disconnected'}
        $script:received.Add($line)
        if($line -match $pattern){return $line}
    }
    throw ('Timed out waiting for '+$pattern)
}
$client=[Net.Sockets.TcpClient]::new()
$reader=$null;$writer=$null
try{
    $connect=$client.ConnectAsync($RobotAddress,80)
    if(-not $connect.Wait(5000)){throw 'Robot connection timeout'}
    $connect.GetAwaiter().GetResult()|Out-Null
    $client.ReceiveTimeout=250
    $reader=[IO.StreamReader]::new($client.GetStream())
    $writer=[IO.StreamWriter]::new($client.GetStream(),[Text.UTF8Encoding]::new($false))
    $writer.AutoFlush=$true;$writer.NewLine="`n"
    $hello=Read-MatchingLine $reader '^CTRL HELLO [0-9a-f]{16} SQUARE_REMOTE_V3$' 5
    $nonce=($hello -split ' ')[2]
    $writer.WriteLine('AUTH '+$nonce+' '+$key)
    $null=Read-MatchingLine $reader ('^CTRL READY '+$nonce+'$') 3
    # Establish an explicitly acknowledged stopped state before idle checks.
    # This also clears a latched startup-stop error only if zero-PWM succeeds.
    $writer.WriteLine('STOP '+$nonce+' 1')
    $null=Read-MatchingLine $reader ('^CTRL STOPPED '+$nonce+'$') 3
    $null=Read-MatchingLine $reader '^\d+,CW,\d+,0,waiting,' 4
    for($sequence=2;$sequence -le 7;$sequence++){
        $writer.WriteLine('HEARTBEAT '+$nonce+' '+$sequence)
        $null=Read-MatchingLine $reader '^\d+,CW,\d+,0,waiting,' 2
    }
    $writer.WriteLine('STOP '+$nonce+' 8')
    $null=Read-MatchingLine $reader ('^CTRL STOPPED '+$nonce+'$') 3
    $null=Read-MatchingLine $reader '^\d+,CW,\d+,0,waiting,' 4
}finally{
    if($writer){$writer.Dispose()};if($reader){$reader.Dispose()};$client.Dispose()
}
$frames=@($script:received|Where-Object{$_ -match '^\d+,' -and ($_ -split ',').Count -eq 13})
if($frames.Count -lt 5){throw 'Too few telemetry records'}
$unexpected=@($frames|Where-Object{$f=$_ -split ',';$f[0] -ne '0' -or $f[3] -eq '1' -or $f[11] -ne '0' -or $f[12] -ne '0'})
if($unexpected.Count){throw 'Unexpected trial or motor command in non-start integration check'}
$logPath=Join-Path $taskRoot ('knowledge-base\square_remote_integration_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
[IO.File]::WriteAllLines($logPath,$script:received,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{handshake='PASS';heartbeat='PASS';stop_acknowledgment='PASS';valid_frames=$frames.Count;nonzero_pwm_records=0;start_commands_sent=0;received_log=$logPath}
