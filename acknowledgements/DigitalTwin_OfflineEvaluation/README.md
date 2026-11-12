# Square V3 数字孪生离线评估

这是 Yanxin Luo 当前正方形数字孪生工作的组内交接包，日期：2026-11-12

`SquareReplayEvaluation.java` 是共享包中同名离线评估脚本的修改版。它复用共享包的 V3 控制器、电机模型、里程计模型和遥测解析器。模型从实机第一条运行记录的位姿和编码器计数初始化，此后每 10 ms 独立推进。脚本只读取文件。

## 运行

在项目最外层目录打开 PowerShell。以下命令使用共享包预编译的孪生类和已安装的 Processing，并回放包内的历史 V2 日志。Processing 安装在其他位置时，将安装目录传给 `Resolve-Processing`。

```powershell
$review = (Resolve-Path '.\DigitalTwin_OfflineEvaluation').Path
$share = (Get-ChildItem -Recurse -Filter OVERVIEW_EN.md | Select-Object -First 1).Directory.FullName
. (Join-Path $share 'tools\Processing-Paths.ps1')
$processing = Resolve-Processing
$cp = Processing-ClassPath $processing (Join-Path $share 'app\classes')
$classes = Join-Path $review 'classes'
New-Item -ItemType Directory -Force $classes | Out-Null
& (Join-Path $processing.Bin 'javac.exe') -cp $cp -d $classes (Join-Path $review 'SquareReplayEvaluation.java')
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
$log = Join-Path $share 'knowledge-base\square-corner-fix-20261112\source_square_v2.csv'
& (Join-Path $processing.Bin 'java.exe') '-Djava.awt.headless=true' -cp "$classes;$cp" SquareReplayEvaluation $log (Join-Path $review 'results')
```

有新 V3 数据后，把 `$log` 换成该 CSV 的路径。脚本使用共享包的 13 列方形遥测格式，只评估有空闲记录作为起始依据的顺时针试验。只录到部分过程的试验可能在轨迹 CSV 中留下已有采样点，缺少停止记录的试验不会生成汇总行。

## 输出

- `square_trace.csv` 记录每个实机采样时刻的编码器里程计和最近的孪生位姿。孪生先结束时，后续行保留它的终止位姿，并在 `twin_pose_ms` 保留终止时刻。
- `square_metrics.csv` 的 `position_rmse_mm` 对运行中的遥测样本计算位置 RMSE。`position_gap_at_robot_stop_mm` 是实机停止记录对应的同一时刻间距。
- `twin_stop_ms` 和 `twin_stop_reason` 由孪生自身运行结果决定。双方都报告完成时，额外输出完成时间差、各自完成时的终点距离和航向差。时间差和航向差均按“孪生减实机”计算。故障试验保留停止原因和同时间比较，完成指标留空。

实机位置和朝向来自编码器里程计。历史 V2 日志可以用来检查脚本行为。评价 V3 对真实路径的预测精度需要另采 V3 数据并加入独立位置测量。
