# 致谢 / Acknowledgements

感谢在这个小车项目中分享代码、思路和经验的朋友们。

Thank you to the friends who shared code, ideas and experience throughout this robot-car project.

感谢 **Yanxin Luo** 分享数字孪生离线评估脚本及使用说明，帮助我们区分小车停车时的差距，以及模型独立完成后的用时、终点和方向差异，也让提前结束和失败记录的处理更加清楚。

Thank you to **Yanxin Luo** for sharing the offline digital-twin evaluator and its guidance. This helped us distinguish the gap at robot stopping from differences in time, endpoint and heading at independent model completion, and clarify the handling of early completion and failed runs.

感谢 **miaoyuwang** 分享最初的 **StampC3_SquareBenchmark** 工程，为正方形路径、编码器里程计和 Wi-Fi 数据记录提供了起始参考，也为后续小车与数字孪生的联调提供了基础。

Thank you to **miaoyuwang** for sharing the initial **StampC3_SquareBenchmark** project, which provided a starting reference for square-path motion, encoder odometry and Wi-Fi data recording, and supported the later robot/digital-twin integration.

也感谢课程团队提供的机器人接口和学习资料，以及小组交流中的帮助与建议。

We also thank the course team for the robot interfaces and learning materials, and the group for helpful discussions and suggestions.

## 相关资料 / Related material

Yanxin Luo 的原交接文件与校验记录完整保存在以下位置：

Yanxin Luo's original handoff files and hashes are preserved here:

- [原交接说明 / Original handoff](acknowledgements/DigitalTwin_OfflineEvaluation/README.md)
- [原始评估脚本 / Original evaluator](acknowledgements/DigitalTwin_OfflineEvaluation/SquareReplayEvaluation.java)
- [文件校验记录 / File provenance](acknowledgements/DigitalTwin_OfflineEvaluation/PROVENANCE.json)
- [离线评估使用说明 / Offline evaluation guide](docs/OFFLINE_EVALUATION.md)

初始工程名称为 `StampC3_SquareBenchmark`；本仓库中的后续固件位于 [StampC3_LPath](robot-programs/StampC3_LPath/)。课程与代码来源见 [SOURCES_AND_CHANGES.md](SOURCES_AND_CHANGES.md)。

The initial project was named `StampC3_SquareBenchmark`; the later adapted firmware is in [StampC3_LPath](robot-programs/StampC3_LPath/). See [SOURCES_AND_CHANGES.md](SOURCES_AND_CHANGES.md) for course and code provenance.

本仓库的后续整理、检查和说明使用了 AI 辅助。

Subsequent repository preparation, checks and documentation used AI assistance.
