param([string]$ProcessingHome,[switch]$Live,[string]$RobotHost)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Processing-Paths.ps1')
$pkg=Split-Path -Parent $PSScriptRoot
$processing=Resolve-Processing $ProcessingHome
$classes=Join-Path $pkg 'app\classes'
$sketch=Join-Path $pkg 'robot-programs\DigitalTwin_LPath'
if(-not(Test-Path -LiteralPath (Join-Path $classes 'DigitalTwin_LPath.class'))){throw 'Compiled app missing. Run tools/Build-Twin.ps1 first.'}
$newest=Get-ChildItem -LiteralPath $sketch -Filter '*.pde' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if($newest.LastWriteTime -gt (Get-Item -LiteralPath (Join-Path $classes 'DigitalTwin_LPath.class')).LastWriteTime.AddSeconds(3)){throw 'Source changed: rebuild with tools/Build-Twin.ps1 first.'}
if($Live -and $RobotHost){
 if($RobotHost -notmatch '^[A-Za-z0-9.-]{1,253}$'){throw 'Use a numeric robot IP or hostname.'}
 [IO.File]::WriteAllText((Join-Path $sketch 'robot-host.txt'),$RobotHost+"`n",[Text.UTF8Encoding]::new($false))
}
if($Live -and -not(Test-Path -LiteralPath (Join-Path $sketch 'robot-control.key'))){throw 'Pair YOUR robot first with analysis/pair_lpath_control.ps1. See README.'}
$cp=Processing-ClassPath $processing $classes
$demo=if($Live){'false'}else{'true'}
$logDir=Join-Path $pkg 'run-logs';New-Item -ItemType Directory -Path $logDir -Force|Out-Null
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$out=Join-Path $logDir ($stamp+'.out.log');$err=Join-Path $logDir ($stamp+'.err.log')
$p=Start-Process -FilePath (Join-Path $processing.Bin 'javaw.exe') -ArgumentList @("-Dsquare.demo=$demo",'-cp',('"'+$cp+'"'),'processing.core.PApplet',('"--sketch-path='+$sketch+'"'),'DigitalTwin_LPath') -WorkingDirectory $pkg -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
"mode=$(if($Live){'LIVE: explicit START required'}else{'OFFLINE MODEL DEMO: networking disabled'}); pid=$($p.Id)"
