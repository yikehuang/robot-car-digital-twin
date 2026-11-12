# Square V3: group handoff

The current task is a clockwise square with four requested 200 mm sides and four quarter-turns. Bottom reflectance sensors are not used. The embedded controller uses encoder feedback, separate wheel-rate regulation and headings referenced to the start of the run. The digital twin executes its own controller and motor/odometry model; it does not copy received poses into the prediction.

Data flow: robot encoders -> firmware odometry + feedback controller -> timestamped CSV over TCP -> orange odometry trace. In parallel, the independent desktop controller -> fitted motor model -> simulated odometry -> blue prediction. The grey square is the ideal reference. Device timestamps pace the comparison; completion/error freezes the model at the observed stop boundary.

Earlier V2 data showed approximately 88–89 degree turns and cumulative heading errors. On the latest complete V2 run, heading after corner two was -177.44 degrees instead of -180. Endpoint closure from wheel odometry was 10.49 mm. The old model finished in 9.01 s versus the recorded 10.03 s; route-phase mismatch contributed to the large instantaneous display separation.

A plant-only refit used healthy V2 trials 1 and 4, excluding trial 5 from parameter fitting. Trial 5's position RMSE relative to odometry decreased from 58.06 to 9.15 mm. Endpoint discrepancy did not improve (17.30 to 19.36 mm). Trial 5 had already been inspected during diagnosis, so this is not blind prospective validation. Stalled trials remain excluded from healthy fitting and retained as diagnostics.

V3 therefore also changes control: each corner targets a cumulative heading, straight sections hold their run-referenced heading, and turns use a shared heading-based stopping boundary. Driven response and zero-command decay are modelled separately. Existing authentication, heartbeat lease, disconnect stop, stall/timeout checks and zero-command retries are retained.

The sender verified compilation, firmware upload, idle telemetry, authenticated non-start TCP integration and software scenarios. Physical V3 trajectory accuracy still needs new independently measured runs. Wheel odometry is not external ground truth: slip and incorrect rolling geometry can make both control and plotted estimates wrong.

This share edition adds a network-disabled offline demo and recipient-specific configuration placeholders. The V3 motion/plant logic is preserved. It includes complete relevant source, historical data and reproduction context; it does not include the sender's private pairing key, Wi-Fi credentials or third-party runtimes.
