param([string]$RobotHost='lpath-com7.local',[string]$KeyFile='')
$ErrorActionPreference='Stop'
Set-Location -LiteralPath (Split-Path $PSScriptRoot -Parent)
$pythonCommand=Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCommand) { throw 'Install Python 3 with Tkinter and NumPy first.' }
& $pythonCommand.Source -c 'import numpy, tkinter'
if ($LASTEXITCODE -ne 0) { throw 'Install NumPy: python -m pip install numpy. Tkinter is included in standard Windows Python.' }
$appArgs=@('-m','sensor_map.viewer','--host',$RobotHost)
if ($KeyFile) { $appArgs+=@('--key-file',$KeyFile) }
& $pythonCommand.Source @appArgs
