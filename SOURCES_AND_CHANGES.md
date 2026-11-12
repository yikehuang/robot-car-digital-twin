# Sources and share-package changes

Course source context: University of Bristol Robotics Science & Systems, https://semtm0043-42.github.io/index.html . The working project includes course robot interfaces and a teammate-supplied StampC3 SquareBenchmark, followed by local integration and model/control revisions. The package is a snapshot of Zeqi Dong's working V3 integration; provenance is not a claim that every supplied interface was written by one group member.

The original course checkout's GPL-3.0 license is preserved at course-materials/RoboticsScienceAndSystems/LICENSE. Original interface source comments are retained. Third-party Processing/Java/ESP32 runtimes are not redistributed here.

Share edition changes (only inside this package):

- All private control-key files, existing Wi-Fi passwords, device memory dumps and sender IP override files are omitted.
- Firmware access-point name/password, mDNS name and default profile names are moved into RobotSharedConfig.h with placeholders. Passwords for upstream networks must be provisioned on the recipient's robot.
- Default desktop hostname is square-teammate.local; the sender-specific fallback hostname is removed.
- Windows launchers default to a dedicated offline model demo. In that mode networking and hardware control are disabled. Live mode is explicitly selected with -Live / RUN_LIVE.bat.
- sketch.properties names the actual main sketch. Windows launch/build scripts use package-relative paths, not the sender's E: drive.

V3 motion controller, wheel feedback, fitted plant, parser and stop protections are unchanged from the sender snapshot. PACKAGE_VALIDATION.json records exact checks and hashes. No physical route was run when building this archive.
