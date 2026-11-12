function Resolve-Processing([string]$Requested) {
 $candidates=@($Requested,$env:PROCESSING_HOME,(Join-Path $env:ProgramFiles 'Processing'),(Join-Path $env:LOCALAPPDATA 'Programs\Processing'))
 foreach($p in $candidates){
  if(-not $p -or -not(Test-Path -LiteralPath $p)){continue}
  foreach($relative in @('app\resources\jdk\bin','java\bin','runtime\bin')){
   $bin=Join-Path $p $relative
   if(Test-Path -LiteralPath (Join-Path $bin 'javaw.exe')){
    return [pscustomobject]@{Home=(Resolve-Path -LiteralPath $p).Path;Bin=$bin}
   }
  }
 }
 throw 'Processing was not found. Install Processing 4.5.7, or pass -ProcessingHome pointing to its installation folder.'
}
function Processing-ClassPath($Processing,[string]$Classes) {
 @($Classes,(Join-Path $Processing.Home 'app\*'),(Join-Path $Processing.Home 'app\resources\core\library\*'),(Join-Path $Processing.Home 'app\resources\modes\java\libraries\net\library\*'),(Join-Path $Processing.Home 'core\library\*'),(Join-Path $Processing.Home 'modes\java\libraries\net\library\*')) -join ';'
}
