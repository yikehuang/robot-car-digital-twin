param([string]$Port='COM7')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$keyPath=Join-Path $taskRoot 'robot-programs\DigitalTwin_LPath\robot-control.key'
if(Test-Path -LiteralPath $keyPath){
    $key=[IO.File]::ReadAllText($keyPath).Trim().ToLowerInvariant()
    if($key -notmatch '^[0-9a-f]{32}$'){throw 'Existing private control key is invalid; it was not replaced'}
}else{
    $bytes=New-Object byte[] 16
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
    $key=([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
}
$serial=[IO.Ports.SerialPort]::new($Port,115200)
$serial.DtrEnable=$false;$serial.RtsEnable=$false;$serial.ReadTimeout=200;$serial.NewLine="`n"
try{
    $serial.Open()
    $idle=0;$deadline=[DateTime]::UtcNow.AddSeconds(2)
    while([DateTime]::UtcNow -lt $deadline){
        try{$fields=$serial.ReadLine().Trim() -split ','}catch [TimeoutException]{continue}
        if($fields.Count -eq 13 -and $fields[0] -match '^\d+$'){
            if($fields[3] -ne '0' -or $fields[11] -ne '0' -or $fields[12] -ne '0'){throw 'Robot must be idle with zero PWM before pairing'}
            $idle++
        }
    }
    if($idle -lt 3){throw 'No fresh idle telemetry; pairing cancelled'}
    $serial.WriteLine('NET CONTROLTEST')
    $passed=$false;$deadline=[DateTime]::UtcNow.AddSeconds(3)
    while([DateTime]::UtcNow -lt $deadline){
        try{$line=$serial.ReadLine().Trim()}catch [TimeoutException]{continue}
        if($line -eq 'CONTROL_SELFTEST PASS'){$passed=$true;break}
        if($line -eq 'CONTROL_SELFTEST FAIL'){throw 'Robot command-gate self-test failed'}
    }
    if(-not $passed){throw 'No successful robot command-gate self-test acknowledgment'}
    $serial.WriteLine('NET CONTROLKEY '+$key)
    $saved=$false;$deadline=[DateTime]::UtcNow.AddSeconds(3)
    while([DateTime]::UtcNow -lt $deadline){
        try{$line=$serial.ReadLine().Trim()}catch [TimeoutException]{continue}
        if($line -eq 'CONTROL key_saved_restart_required'){$saved=$true;break}
    }
    if(-not $saved){throw 'Control key was not acknowledged by robot'}
    [IO.File]::WriteAllText($keyPath,$key+"`n",[Text.UTF8Encoding]::new($false))
    [pscustomobject]@{paired=$true;robot_protocol_self_test='PASS';restart_required=$true;private_key_file=$keyPath;motion_commands_sent=0}
}finally{if($serial.IsOpen){$serial.Close()};$serial.Dispose()}
