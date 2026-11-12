param(
 [Parameter(Mandatory=$true)][string]$Telemetry,
 [string]$OutputDirectory,
 [string]$ProcessingHome
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Processing-Paths.ps1')
$pkg=Split-Path -Parent $PSScriptRoot
$inputFile=(Resolve-Path -LiteralPath $Telemetry).Path
if(-not $OutputDirectory){
 $OutputDirectory=Join-Path $pkg ('build\offline-evaluation\'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
}
$outputPath=[IO.Path]::GetFullPath($OutputDirectory)
foreach($name in @('square_metrics.csv','square_trace.csv')){
 if(Test-Path -LiteralPath (Join-Path $outputPath $name)){throw 'Evaluation CSV already exists. Choose a new output directory.'}
}
$processing=Resolve-Processing $ProcessingHome
$classes=Join-Path $pkg 'build\offline-evaluation-classes'
New-Item -ItemType Directory -Path $classes -Force|Out-Null
$cp=Processing-ClassPath $processing (Join-Path $pkg 'app\classes')
& (Join-Path $processing.Bin 'javac.exe') -encoding UTF-8 -cp $cp -d $classes (Join-Path $pkg 'analysis\LegacySquareReplayEvaluation.java') (Join-Path $pkg 'analysis\SquareReplayEvaluation.java')
if($LASTEXITCODE -ne 0){throw 'Offline evaluator compilation failed'}
& (Join-Path $processing.Bin 'java.exe') '-Djava.awt.headless=true' -cp "$classes;$cp" SquareReplayEvaluation $inputFile $outputPath
if($LASTEXITCODE -ne 0){throw 'Offline evaluation failed'}
[pscustomobject]@{input=$inputFile;output=$outputPath;metrics=(Join-Path $outputPath 'square_metrics.csv');trace=(Join-Path $outputPath 'square_trace.csv');hardware_commands_sent=0}
