# Robot Car Digital Twin

An encoder-controlled robot car and an independent Processing digital twin for a clockwise **200 mm square**. Built for group work in University of Bristol Robotics Science & Systems (SEMTM0043/SEMTM42).

[中文使用说明](README_先看这里.md) · [Technical overview](OVERVIEW_EN.md) · [Dependencies](DEPENDENCIES.md) · [Physical validation](PHYSICAL_VALIDATION.md)

![Offline model demonstration — not a measured physical trajectory](screenshots/offline_model_demo.png)

## Try the offline demo

1. Download the repository with **Code → Download ZIP** and extract it completely.
2. Install **Processing 4.5.7** with its bundled Java runtime and Network library.
3. On Windows, double-click **RUN_DEMO.bat**. The demo computes the model trajectory with networking and hardware control disabled.

For a nonstandard Processing installation, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Run-Twin.ps1 -ProcessingHome "C:\Path\To\Processing"
```

The included prebuilt Java classes require Java 17 or later and the Processing libraries. They are provided for demo convenience; matching source is included. Rebuild after source changes using `tools/Build-Twin.ps1`, or open `robot-programs/DigitalTwin_LPath/DigitalTwin_LPath.pde` in Processing. Running the source directly defaults to Live mode, which still requires pairing and an explicit START.

## What the project contains

- **Robot firmware:** StampC3 control through the course robot interface, four straight segments and four clockwise quarter-turns, wheel-rate feedback, and headings referenced to the run start.
- **Independent digital twin:** directional motor-response gains, separate driven/zero-command dynamics, differential-drive odometry and its own feedback controller.
- **Live comparison:** authenticated START/STOP over Wi-Fi/TCP, device-clock pacing, recorded CSV, target/odometry/model traces, disconnect and heartbeat stopping.
- **Evidence and analysis:** historical V2 encoder data, stage-by-stage error diagnosis, parameter fitting and verification records.

| Path | Purpose |
|---|---|
| `robot-programs/StampC3_LPath/` | Complete embedded source; configure `RobotSharedConfig.h` for your robot |
| `robot-programs/DigitalTwin_LPath/` | Complete Processing source; historical folder name, current square route |
| `tools/` | Portable Windows launch/build scripts |
| `analysis/` | Calibration, pairing and software checks |
| `knowledge-base/square-corner-fix-20261112/` | Frozen V2 evidence and diagnosis |
| `app/classes/`, `app/source/` | Prebuilt desktop classes and matching generated Java |

## Connect your own robot

Follow [the setup guide](README_先看这里.md#用你自己的小车运行). Set your own hotspot identity/password and mDNS name in `RobotSharedConfig.h`, flash the StampC3, pair it locally over USB, and configure its Wi-Fi profiles. PC and robot must be on a network allowing peer access. Use **RUN_LIVE.bat** only after setup. Each robot should have its own pairing key and calibration; sender credentials are excluded.

Uploading/pairing requires the wheels to be supported clear of the surface. Physical runs require a clear level test area and a deliberate START. STOP, Space and Esc request stopping. Use one TCP client at a time.

## Read the plotted lines correctly

- **Grey dashed:** the ideal requested square.
- **Blue:** independent model prediction.
- **Orange:** position estimated from robot wheel encoders.

Wheel odometry is not independent physical ground truth. Slip or incorrect rolling geometry can make the estimate wrong even when the plotted paths agree. Validate physical motion using measured references and fixed overhead video; see [PHYSICAL_VALIDATION.md](PHYSICAL_VALIDATION.md).

## Validation status

The sender verified firmware/whole-sketch compilation, upload, idle telemetry, authenticated non-start TCP integration and software checks. The share edition additionally passed its firmware build, complete desktop build, offline GUI launch, unpaired-live blocking and launch after extraction to a path containing spaces and Chinese characters. See [PACKAGE_VALIDATION.json](PACKAGE_VALIDATION.json).

Historical V2 plant fitting used trials 1 and 4 and excluded trial 5 from parameter fitting. The trial-5 time-aligned position RMSE relative to wheel odometry decreased from 58.06 to 9.15 mm, while stopping-frame endpoint discrepancy did not improve. This is historical model-versus-odometry evidence, not physical V3 accuracy. New V3 runs with independent distance/heading measurements are still required.

## Provenance and license

This snapshot combines course interfaces, a teammate-supplied benchmark and Zeqi Dong's subsequent local integration/model/control work. See [SOURCES_AND_CHANGES.md](SOURCES_AND_CHANGES.md) and the preserved [course GPL-3.0 license](LICENSE). Third-party Processing, Java and ESP32 runtimes are installed separately.

`SHARE_PACKAGE_MANIFEST.sha256` preserves checksums of the original team-share package; GitHub-specific README, license placement and ignore/attribute rules are later packaging additions.
