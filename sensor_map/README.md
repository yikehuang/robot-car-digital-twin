# 传感器地图定位 / Sensor-map localisation (experimental)

目标是用真实五探头读数与编码器更新电脑轨迹；当前不把定位结果反馈给电机控制。固件仍执行原有四条 200 mm 直线及四次右转。地图本身不能保证小车走成正方形。

The new pipeline uses measured five-channel reflectance and encoder counts. The existing V3 motor controller is unchanged. Map localisation is not yet used for steering. Neither the map nor a square-looking estimate guarantees a physically square path.

## 打印 / Print

- 首选 [A3 横向地图](../maps/coded_grid_v2/CodedGrid_A3_100percent.pdf)，420 × 297 mm。
- 只有 A4 打印机时用 [四张 A4 拼接版](../maps/coded_grid_v2/CodedGrid_A4_4tiles_100percent.pdf)，横向、100% 实际大小；重叠区 20 mm，对齐相同图案，从背面固定。不要让纸层接缝凸起。
- 同时打印 [A4 黑白校准纸](../maps/coded_grid_v2/Calibration_A4_100percent.pdf)。与地图用同种纸和墨。
- 关闭“适合页面”。量校准纸的 100 mm 标尺，并抽查地图 10 mm 单格。图案不能被打印机裁剪。格子为 28 × 40、每格 10 mm，图案区 400 × 280 mm。
- [起点示意图](../maps/coded_grid_v2/start_reference_NOT_for_print.png) 仅供查看，**不要打印代替地图**。绿色圈为轮轴中点，距 A3 左边 110 mm、上边 48.5 mm；车头向右。地图上不额外画黑色定位点。

Print at actual size / 100%, never fit-to-page. Verify the 100 mm calibration scale and 10 mm cells with a ruler. Prefer one A3 sheet; the four A4 sheets overlap by 20 mm. Use the same paper and ink for calibration. The illustrated green start mark is a screen-only reference: axle centre 110 mm from the paper's left edge and 48.5 mm from its top edge, facing right. Keep seam steps and extra markings outside the sensing area.

## 软件与实机 / Setup

1. 使用 Python 3（含 Tkinter），安装 `python -m pip install numpy`。生成 PDF 才另需 `reportlab pymupdf`。
2. 新固件是 `robot-programs/StampC3_GridTelemetry/StampC3_GridTelemetry.ino`。组员先在 `RobotSharedConfig.h` 配置自己的设备；Wi-Fi 凭据在设备上设置，私钥按现有配对流程生成。仓库不含本人的配网密码或控制私钥。
3. 关闭旧 Processing Live 窗口；TCP 80 只支持一个客户端。电脑和小车连同一网络。运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Run-SensorMap.ps1 -RobotHost "YOUR_ROBOT_IP" -KeyFile "C:\private\robot-control.key"
```

也可 `python -m sensor_map.viewer --host YOUR_ROBOT_IP`；缺少配对私钥时只读数据，不能启动。`--geometry` 可指定自己的配置文件。

4. 小车恢复正常落地高度，电机停止。整排探头置于校准纸白色方框内部，点击 Capture WHITE，等 60 个不同源时间戳样本完成；再置于黑色方块内部点击 Capture BLACK。读取时手离开，纸、供电、光照、落地姿态一致。轮子悬空采集只验证链路，不能作为落地运行校准。
5. 将**轮轴中点**放到上述起点、朝右，勾选位置确认，点击 Initialize at START。出现地图匹配后观察绿色估计位置。只有明确点 START 才请求实机运动；空格/Esc/STOP 停车。关闭窗口发送 STOP，固件还保留失联与心跳超时停车。
6. 在安全平面上先做短程，录像或手工记录独立参考位置，再测试完整路线。不要将画出来的轨迹本身作为正确性的证据。

Install NumPy and standard Python/Tkinter. Flash the optional GRID firmware with your own shared configuration, then close other live clients and connect both devices to the same network. Without a paired private key, viewing is read-only. Calibrate each target using 60 distinct source timestamps at normal operating height. Initialise only after physically placing the axle at the stated start and heading. START is explicit; STOP, Space, Esc, closing the viewer and command timeout stop the robot. Validate short motions against independent measurements before a full run.

## 数据意味着什么 / Interpretation

- 五个探头提供黑白响应，不直接读出格子编号。连续观测与编码器传播在已知起点附近进行粒子滤波，匹配地图；格子编号是**推断值**。没有把控制阶段、目标正方形或 PWM 作为位置输入。
- 相同黑白组合可以出现在不同位置。图案通过全部 3456 个理想 5×5 方块的四向旋转唯一性检查；这**不等于**五个稀疏探头的一帧数据唯一，更不保证任意角度全局定位。当前不支持绑架恢复或未知起点全局搜索。
- 绿色线是 **sensor-fused estimate**，不是无模型直接测量，更不是外部 ground truth。编码器仍用于帧间传播。缺少新时间戳、地图信息不足、越界、分布过宽或明显不匹配时不显示有效位置，并断开轨迹，避免伪造连续线路。
- 速度和转速来自至少 300 ms 的稳定融合位置历史；数据不够时显示 pending。色差本身不是速度。滤波分布宽度只反映模型内不确定性，不是实际精度保证。
- `geometry.example.json` 使用用户估计：整排跨度约 60 mm、轮轴中点到中间探头约 30 mm。中间探头等间距（15 mm）与有效光斑 1 mm 为待验证近似；名义轮半径 16.1 mm、轮距 83.6 mm、358.3 counts/revolution 也要按各车验证。**尚未确认 DN1..DN5 对实际左右探头的逐一对应**，正式定位前逐个遮挡核对。不要把车头边缘当轮轴或探头中心。
- 历史个人实验 15 mm 探头高度不自动等于当前落地高度。高度、打印反射率、光斑、灯光、轮子打滑和几何误差都会影响定位。转角处外侧探头可能短暂离开有效图案，软件会排除越界读数。

Cells are inferred from sequential reflectance likelihood and encoder propagation near a known start. No PWM-derived pose or square stage is fed to the localiser. A unique ideal 5×5 patch does not imply a unique five-sensor observation. Sparse sampling, aliasing, surface changes and incorrect geometry can produce plausible but wrong estimates. Green traces are model-dependent sensor-fused estimates, not external ground truth. No accepted position is drawn for rejected observations; velocities require stable temporal matches. Geometry, channel ordering and optical footprint require physical checks before accuracy claims.

## 协议与记录 / Protocol and evidence

20 字段、CSV，约每 20 ms 请求一次：

```text
GRID1,sequence,time_ms,encoder_ok,left_count,right_count,sensor_ok,sensor_timestamp_us,new_sensor_stamp,dn1,dn2,dn3,dn4,dn5,trial,stage,state,left_pwm,right_pwm,sensor_read_us
```

`sensor_timestamp_us` 是 32U4 middleware 快照提供的时间戳。`new_sensor_stamp` 只表示它相对上一快照变化，不能独立证明光学采样时刻；`sensor_read_us` 是 ESP32 读取请求耗时。编码器结构没有源时间戳，只有主控读取时间。I2C 成功不等于全新光学读数。读取失败写 NA，不填零；USB 忙时整帧丢弃，sequence 可揭示缺帧。TCP 使用现有认证、单调序号与 1.5 s 控制租约；不会因连接而自动启动。

`run-logs/sensor-map-*` 保存 `observations.csv`、接收原文、`estimates.jsonl`、地图/几何文件哈希、校准中位数/噪声及起点确认。该目录被 Git 忽略。没有接受的估计写 JSON null，不补线。源时间与电脑接收时间分别保存。

The timestamps describe the middleware snapshot, not an independently verified optical exposure. Encoder samples have no source timestamp. Failed sensor reads are NA. Full USB frames may be dropped under buffer pressure; sequence gaps expose loss. Logs preserve raw observations, estimated outputs, configuration hashes, calibration statistics and initial-placement confirmation. Local keys and execution logs are excluded from version control.

2026-11-12：本车固件编译/烧录校验通过；385 帧静止 USB 记录中编码器不变、五路读取成功、385 个不同源时间戳、PWM 全零；新 GUI 实际收到 Wi-Fi GRID1。软件检查含解析、旧时间戳拒绝、重启、未校准、回环网络无自动启动、理想图案唯一性及合成直线路径。**这些不证明实车地图定位精度；完整打印地图测试尚未完成。** 合成数据与实机记录不得混同。

Software checks: `python analysis/check_sensor_map.py`. The checks use synthetic data and a local mock TCP peer; they never start physical hardware. Firmware delivery and stationary acquisition are verified, but printed-map physical localisation, velocity and turning accuracy remain unvalidated. Compare against overhead video or ruler measurements independent of encoders. Report along/cross-track position error, turn error, valid-match coverage and failure cases; do not select only square-looking runs.

硬件参考 / Hardware reference: [Pololu 3pi+ guide](https://www.pololu.com/docs/0J83/all), [line sensor library](https://pololu.github.io/pololu-3pi-plus-32u4-arduino-library/class_pololu3pi_plus32_u4_1_1_line_sensors.html). Course API implementation is included in the firmware source. This is a group-project prototype, not a confirmed course requirement.
