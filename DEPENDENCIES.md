# Dependencies

- Desktop: Processing 4.5.7 with its bundled Java runtime and Network library (net.jar), as tested on the sender PC. Processing and its runtime/libraries are not bundled. Install them separately. Windows launchers locate Processing automatically or accept -ProcessingHome.
- Firmware: M5Stack ESP32 board package, Stamp C3. Sender used m5stack:esp32 3.3.9, board m5stack_stamp_c3, CDCOnBoot=default, FlashMode=dio, UploadSpeed=921600. Choose your own actual serial port. Arduino IDE / CLI and board packages are not bundled.
- Optional data analysis: Python 3 with NumPy and SciPy. Needed only to rerun the encoder-response fitting; not needed for the demo or live GUI.
- Phone/camera and a ruler/grid are needed for independent physical path validation. They are not needed to view the model demo.
