# 离线评估 / Offline evaluation

本工具合并自用户提供的 `DigitalTwin_OfflineEvaluation.zip`；原交接说明署名 Yanxin Luo。原文件及校验值保存在 [contributions/DigitalTwin_OfflineEvaluation](../contributions/DigitalTwin_OfflineEvaluation/)。它读取 CSV，使用当前模型独立运行，不连接或控制小车。

This tool integrates the supplied `DigitalTwin_OfflineEvaluation.zip`; its handoff credits Yanxin Luo. The original files and hashes are preserved in [contributions/DigitalTwin_OfflineEvaluation](../contributions/DigitalTwin_OfflineEvaluation/). It reads CSV and runs the current model independently, without connecting to or commanding hardware.

## 运行 / Run

在仓库根目录执行。以下示例使用历史 V2 数据，只验证评估流程；不能据此宣称 V3 对真实路线的预测精度。

Run from the repository root. This example uses historical V2 data to exercise the evaluation pipeline; it does not validate V3 predictions of physical trajectories.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Evaluate-Offline.ps1 -Telemetry .\knowledge-base\square-corner-fix-20261112\source_square_v2.csv
```

可选参数：`-ProcessingHome "C:\Path\To\Processing"` 指定 Processing 安装目录；`-OutputDirectory "C:\Path\To\NewResults"` 指定一个新的输出目录。默认结果保存在 `build/offline-evaluation/时间戳/`。脚本编译评估器后使用分享包中的桌面类运行；若已修改模型源码，应先执行 `tools/Build-Twin.ps1`。

Optional parameters: `-ProcessingHome "C:\Path\To\Processing"` selects the Processing installation; `-OutputDirectory "C:\Path\To\NewResults"` selects a new output directory. By default, results go to `build/offline-evaluation/<timestamp>/`. The runner compiles the evaluator and uses the packaged desktop classes; rebuild with `tools/Build-Twin.ps1` first if model source has changed.

## 两类误差 / Two kinds of comparison

| 输出字段 / Field | 中文含义 | English meaning |
|---|---|---|
| `position_rmse_mm` | 对所有有效 RUNNING 遥测行计算的位置 RMSE | Position RMSE across accepted RUNNING telemetry rows |
| `position_gap_at_robot_stop_mm` | 实机首条停止记录时，里程计与模型的同时间位置差 | Model-versus-odometry position gap at the first recorded robot stop |
| `twin_stop_ms`、`twin_stop_reason` | 模型独立运行至结束的时间和原因 | Independent model termination time and reason |
| `completion_time_delta_ms` | 模型完成时间减去实机完成时间；负值表示模型先完成 | Model minus robot completion time; negative means model finishes first |
| `completion_endpoint_gap_mm` | 两者各自完成时的终点差，属于异时刻比较 | Endpoint gap at their respective completion times, a different-time comparison |
| `completion_heading_delta_deg` | 各自完成时的航向差，归一到 ±180° | Heading difference at respective completion, wrapped to ±180 degrees |

输出 `square_metrics.csv` 和 `square_trace.csv`。轨迹表的 `twin_pose_ms` 保留模型实际对应时刻：模型先结束时保持其终止位姿，而不是伪装成继续运动。模型比小车晚结束时，先记录小车停止时的差距，再让模型独立完成。仅双方都成功完成时，才填写各自完成时的比较字段。

Outputs are `square_metrics.csv` and `square_trace.csv`. The trace's `twin_pose_ms` preserves the model pose time: if the model finishes early, its terminal pose is held. If it finishes later, the same-time gap is recorded before continuing to model completion. Respective-completion fields are populated only when both runs complete successfully.

## 数据条件 / Data conditions

- 使用现有 13 列 benchmark CSV，试验前须有有效 WAITING 记录。中途接入、逆时针、缺失开始或停止记录的数据不会被当成完整成功试验。
- 有运行但缺失终止记录时，保留可用轨迹行，不输出该试验的汇总行。失败试验保留首次停止原因；后续 STOP 不覆盖它。
- 模型每 10 ms 推进，时间对照可能存在不足 10 ms 的步长差。RMSE 按收到的遥测行等权计算，包含同时间戳的重复行，并非均匀时间加权误差。
- 原 CSV 没有控制器版本字段；请自行确认数据与编译模型使用相同控制器。V2 数据与 V3 模型的对照只适合流程检查。
- 实测位置来自轮式里程计。真实位置误差仍需外部位置与方向测量。

- Uses the existing 13-column benchmark CSV and requires valid WAITING data before a run. Mid-run connections, anticlockwise data and missing boundaries are not treated as complete successful trials.
- A run missing its terminal record retains available trace rows but has no summary row. Failed runs keep their first stopping reason; later STOP records do not replace it.
- The model advances in 10 ms steps, so aligned comparisons may differ by less than one step. RMSE weights received telemetry rows equally, including same-timestamp duplicates, rather than weighting uniform time intervals.
- CSV does not identify the controller version. Confirm that recorded data and compiled model use matching control logic. V2-data/V3-model comparisons are pipeline checks only.
- Recorded pose is wheel odometry. Physical position error requires independent position/heading measurements.

## 兼容与检查 / Compatibility and checks

新的两参数 Java 入口输出上述新表格。原三参数调用（CSV、目录、标签）仍转交 `LegacySquareReplayEvaluation`，保留历史文件名和列格式。旧的实机 Live 显示仍按实机停止边界冻结；离线评估的模型独立完成不会改变在线控制行为。

The new two-argument Java entry produces the new tables. Existing three-argument calls (CSV, directory, label) dispatch to `LegacySquareReplayEvaluation`, preserving historical output names and columns. Live display still freezes at the robot stopping boundary; independent completion in offline evaluation does not change online control.

八项回归检查覆盖提前/延后完成、失败原因、缺失边界、方向不匹配、重启和旧接口。检查脚本为 `analysis/test_square_offline_evaluation.py`，仅使用临时合成 CSV 和文件回放，不发送硬件指令。

Eight regression checks cover early/late completion, failure reasons, missing boundaries, direction mismatch, reboot and legacy compatibility. `analysis/test_square_offline_evaluation.py` uses temporary synthetic CSVs and file replay only, with no hardware commands.
