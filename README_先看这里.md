# 机器人小组项目分享包 — Square V3

这是 Zeqi Dong 当前正方形数字孪生工作的组内交接包，日期：2026-11-12。

## 先看我做了什么

- 路线：四条 200 mm 直线、四次顺时针 90° 转向，最后请求回到初始位置与朝向。
- 控制：左右轮各自根据编码器调速；每条边保持以起始方向为参照的目标朝向；转角目标为 -90/-180/-270/-360°，减少前一转角误差的累积。
- 数字孪生：独立计算控制命令和运动，左右轮使用不同响应参数；通电响应和停止后的滑行分别建模。
- 联网：小车接入所配置的 Wi-Fi，保留自身热点；PC 通过 TCP 接收数据、发送认证后的 START/STOP。断连/心跳超时请求停车。
- 数据：有原始 V2 实测编码器记录、逐路段分析、参数拟合及软件验证记录。

## 最快查看：不需要小车

1. 完整解压本包，不要只从 ZIP 中双击内部文件。
2. 安装 Processing 4.5.7（依赖见 DEPENDENCIES.md）。
3. Windows 双击 **RUN_DEMO.bat**。它播放独立模型的正方形路线，不连接任何小车。
4. 安装位置未自动找到时，在本目录打开 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Run-Twin.ps1 -ProcessingHome "C:\你的Processing目录"
```

灰色虚线是理想目标，蓝色是模型预测。离线演示不是一次实机实验，也不证明小车能走同样的正方形。STOP 会停止演示；需要重看时关闭窗口再启动。

## 文件从哪里看

| 文件/目录 | 内容 |
|---|---|
| OVERVIEW_EN.md | 可用于组内讨论的英文技术概述 |
| robot-programs/DigitalTwin_LPath/ | Processing 完整源码，名字保留历史 LPath，但当前运行正方形 |
| robot-programs/StampC3_LPath/ | StampC3 完整固件源码与共享配置 |
| app/classes/ | 本包源码编译的 Java 类；启动脚本使用它们 |
| knowledge-base/square-corner-fix-20261112/ | 冻结 V2 数据、误差分析、拟合与发送者验证记录 |
| knowledge-base/firmware-backups/.../DigitalTwin_LPath/ | 生成旧数据的 V2 模型/控制器源码，供复现对照 |
| analysis/ | 参数拟合、软件检查、接收端配对脚本 |
| PHYSICAL_VALIDATION.md | 如何确认实机路线与屏幕轨迹对应 |
| PACKAGE_VALIDATION.json、SHARE_PACKAGE_MANIFEST.sha256 | 原分享包的编译/检查与文件校验记录（GitHub 版有说明文件调整） |

## 用你自己的小车运行

1. 编辑固件中的 RobotSharedConfig.h，给小车设置独立的热点名称、密码及 mDNS 名称。此包不包含发送者的网络密码或私人控制密钥。
2. 驱动轮悬空，使用课程要求的主控/小车固件环境，上传 StampC3_LPath.ino。这里控制的是课程既有 32U4/I2C 接口；不要把该 StampC3 草图上传到 32U4。
3. 新机器人需先做本地配对。在本目录 PowerShell 中执行（替换为自己的端口）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\analysis\pair_lpath_control.ps1 -Port COM5
```

配对脚本仅在有新鲜 WAITING、零 PWM 记录时写入新配对密钥；完成后按提示重启 StampC3。若初始化报告 initial_stop_failed，先保持悬空、检查小车电源/I2C并重启，确认恢复 WAITING。不要绕过保护。

4. 电脑先接入你的小车热点，在浏览器打开 http://192.168.4.1:8080 ，用户名 robot，密码为你自己设置的热点密码。设置 primary/backup 网络与密码。ESP32-C3 需要 2.4 GHz；电脑和小车应在可互访的同一局域网。
5. 小车热点直连测试可使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Run-Twin.ps1 -Live -RobotHost 192.168.4.1
```

接入上游网络后，用你自己的 mDNS 名称或当前小车 IP，例如 `-RobotHost square-alice.local`。也可以编辑生成的 robot-host.txt。电脑只切换 Wi-Fi、而小车留在另一个网络时，原 IP 通常就无法访问。

6. 确认窗口接收实时数据并显示 Remote control ready。放到平整开阔地面，电池供电、移除拖拽 USB，再明确点击 START REAL ROBOT。STOP、空格、Esc 请求停车。

一次只连接一个 TCP 客户端。不要一边用 GUI 控制，一边打开额外 TCP 接收器。

## 已验证什么，还有哪些限制

- 发送者 V3：固件/完整桌面程序编译、烧录、认证/心跳/STOP、待机接收以及软件仿真测试已验证。
- 分享包：具体编译/启动检查见 PACKAGE_VALIDATION.json。分享配置不是朋友那台车的物理验证结果。
- 历史 V2 数据的多数转角约 88–89°，存在欠转和阶段时间差。V3针对这些原因修改；它的落地精度仍需要新实验。
- 橙色轨迹是编码器推算，不是相机测得的真实位置。蓝橙接近不能证明小车真实路线准确。
- 参数来自发送者的小车；你的轮径、摩擦、电池、左右轮响应不同，需要单独验证/校准。
- V2 参数留出验证的 RMSE 改善不是 V3 的实机成绩。详见证据文件。

若修改 .pde 源码，先运行 tools/Build-Twin.ps1 更新 app/classes，或直接用 Processing 打开 DigitalTwin_LPath.pde 运行源码。直接在 Processing 点运行默认是 Live 模式，不等同于 RUN_DEMO 的隔离演示模式。
