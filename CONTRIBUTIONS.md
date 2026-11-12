# 小组贡献记录 / Team contributions

本记录依据已提供的源码、交接说明和仓库整合记录，区分组员提供的改进与后续整合工作。

This record distinguishes contributed improvements from subsequent integration work, based on the supplied source, handoff and repository history.

## Yanxin Luo

**贡献：数字孪生离线评估改进 / Contribution: improved offline digital-twin evaluation**  
**交接日期 / Handoff date: 2026-11-12**

原交接包 `DigitalTwin_OfflineEvaluation.zip` 中的说明署名为 **Yanxin Luo**。该贡献提供了修改后的 `SquareReplayEvaluation.java` 及运行和指标说明，复用项目已有的 V3 控制器、电机模型、里程计与遥测解析器。

The supplied `DigitalTwin_OfflineEvaluation.zip` handoff credits **Yanxin Luo**. The contribution provides a revised `SquareReplayEvaluation.java` and usage/metric documentation, reusing the project's existing V3 controller, motor model, odometry and telemetry parser.

| 改进 / Improvement | 中文说明 | English description |
|---|---|---|
| 独立完成评估 / Independent completion | 记录模型自身结束的时间和原因；小车停止后，模型可继续独立运行至结束 | Records the model's own termination time and reason, allowing it to finish independently after the recorded robot stops |
| 区分两类比较 / Separate comparison types | 分别记录小车停车时的同时间位置差，以及双方各自完成时的时间、终点和航向差 | Separates the same-time position gap at robot stopping from time, endpoint and heading differences at respective completion |
| 提前结束处理 / Early model completion | 模型先结束时保留终止位姿，并用 `twin_pose_ms` 明确该位姿对应的模型时刻 | Holds the terminal pose when the model finishes early and records its model time in `twin_pose_ms` |
| 失败与不完整记录 / Failed and incomplete runs | 保留首次失败原因；仅双方成功完成时填写完成对比指标；缺失终止记录时保留已有轨迹，不生成完整汇总行 | Preserves the first failure reason, populates respective-completion comparisons only for matching successful completions, and retains partial traces without a complete summary when termination is missing |
| 可复用的输出与说明 / Reusable outputs and documentation | 输出 `square_metrics.csv`、`square_trace.csv`，并提供运行步骤与指标解释 | Produces `square_metrics.csv` and `square_trace.csv`, with run instructions and metric definitions |

这项贡献帮助小组区分模型与小车的阶段时间差，以及各自完成时的位姿差异。交接说明同时明确：记录位置来自编码器里程计，历史 V2 日志可用于检查流程，V3 真实路线预测仍需新数据和独立位置测量。

This contribution helps distinguish model-versus-robot route-phase differences from pose differences at respective completion. The handoff also identifies the evidence limits: recorded pose is encoder odometry, historical V2 logs can check the pipeline, and V3 physical prediction requires new data and independent position measurements.

### 原始文件与合并位置 / Original files and integration

- [原交接说明 / Original handoff](contributions/DigitalTwin_OfflineEvaluation/README.md)
- [原始评估脚本 / Original evaluator](contributions/DigitalTwin_OfflineEvaluation/SquareReplayEvaluation.java)
- [原文件与压缩包校验记录 / File and archive provenance](contributions/DigitalTwin_OfflineEvaluation/PROVENANCE.json)
- [合并后的评估器 / Integrated evaluator](analysis/SquareReplayEvaluation.java)
- [中英双语使用说明 / Bilingual usage guide](docs/OFFLINE_EVALUATION.md)

原始文件完整保留。当前整合版在原两参数评估行为之外，增加了旧三参数调用的兼容入口。

The original files are preserved intact. The integrated version retains the contributed two-argument evaluation behaviour and adds a compatibility entry for the earlier three-argument invocation.

## Zeqi Dong — 仓库整合 / Repository integration

在本次离线评估合并中，Zeqi Dong 的项目整合工作通过 AI 辅助完成：保存原始贡献及校验值，加入旧接口兼容、便携启动脚本、八项回归检查、中英双语说明，并维护 GitHub 仓库。

For this offline-evaluation integration, Zeqi Dong's project integration used AI assistance to preserve the original contribution and hashes, add legacy compatibility, a portable runner, eight regression checks and bilingual documentation, and maintain the GitHub repository.

相关文件 / Related files:

- [便携评估入口 / Portable runner](tools/Evaluate-Offline.ps1)
- [旧接口兼容 / Legacy compatibility](analysis/LegacySquareReplayEvaluation.java)
- [回归检查 / Regression checks](analysis/test_square_offline_evaluation.py)
- [整合验证记录 / Integration verification](knowledge-base/offline-evaluation-20261112/verification.json)

## 课程与基准代码 / Course and benchmark code

项目还包含课程机器人接口和组员提供的初始基准程序；来源与许可证见 [SOURCES_AND_CHANGES.md](SOURCES_AND_CHANGES.md) 和 [LICENSE](LICENSE)。

The project also includes course robot interfaces and an initial teammate-supplied benchmark. See [SOURCES_AND_CHANGES.md](SOURCES_AND_CHANGES.md) and [LICENSE](LICENSE) for provenance and licensing.
