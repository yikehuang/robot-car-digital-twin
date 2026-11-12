param([string]$ProcessingHome)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Processing-Paths.ps1')
$pkg=Split-Path -Parent $PSScriptRoot;$processing=Resolve-Processing $ProcessingHome
$classes=Join-Path $pkg 'app\classes';$build=Join-Path $pkg 'build\desktop';$sketch=Join-Path $pkg 'robot-programs\DigitalTwin_LPath'
$cp=Processing-ClassPath $processing $classes
$started=Get-Date
& (Join-Path $processing.Bin 'java.exe') -cp $cp processing.mode.java.Commander "--sketch=$sketch" "--output=$build" --force --build
$java=Join-Path $build 'source\DigitalTwin_LPath.java'
if(-not(Test-Path -LiteralPath $java) -or (Get-Item -LiteralPath $java).LastWriteTime -lt $started.AddSeconds(-2)){throw 'Fresh preprocessed source missing. Check Processing installation.'}
# Some Processing installs cannot discover net.jar in native CLI mode. Compile
# the complete fresh generated sketch explicitly against the bundled jars.
New-Item -ItemType Directory -Path $classes -Force|Out-Null
$tests=@('SquareFeedbackSelfTest.java','SquareRemoteControlSelfTest.java','SquareLiveSessionSelfTest.java')|ForEach-Object {Join-Path $pkg ('analysis\'+$_)}
& (Join-Path $processing.Bin 'javac.exe') -encoding UTF-8 -cp $cp -d $classes $java @tests
if($LASTEXITCODE -ne 0){throw 'Whole-sketch compilation failed'}
foreach($test in @('SquareFeedbackSelfTest','SquareRemoteControlSelfTest','SquareLiveSessionSelfTest')){
 & (Join-Path $processing.Bin 'java.exe') -cp $cp $test
 if($LASTEXITCODE -ne 0){throw "Failed: $test"}
}
