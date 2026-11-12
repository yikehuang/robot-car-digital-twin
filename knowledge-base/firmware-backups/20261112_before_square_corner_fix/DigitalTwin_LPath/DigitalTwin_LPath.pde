import processing.net.*;
import processing.core.PApplet;
import java.net.*;

/** @brief Initial application-window width in screen pixels. */
final int WINDOW_WIDTH = 1000;
/** @brief Initial application-window height in screen pixels. */
final int WINDOW_HEIGHT = 800;
/** @brief Initial surface-image x offset from the world origin, in mm. */
final float SURFACE_OFFSET_X_MM = 135.0;
/** @brief Initial surface-image y offset from the world origin, in mm. */
final float SURFACE_OFFSET_Y_MM = 0.0;

/** @brief Application-level owner of the simulated robot and UI. */
Simulator simulator;

/** @brief Configures Processing's initial drawing surface. */
void settings() {
  size(WINDOW_WIDTH, WINDOW_HEIGHT);
}

/** @brief Creates the resizable simulator window and its application state. */
void setup() {
  
  // Keep a normal window (rather than fullscreen) so students can resize it
  // or place it beside their controller code. Starting at the display size
  // gives the same practical benefit as maximising it at launch.
  surface.setResizable(true);
  
  //surface.setSize(displayWidth, displayHeight);
  //surface.setLocation(0, 0);
  surface.setTitle("Group Square - encoder feedback and digital twin");
  simulator = new Simulator(this, SURFACE_OFFSET_X_MM, SURFACE_OFFSET_Y_MM);
  
}

/** @brief Advances the application state and renders one frame. */
void draw() {
  simulator.update();
  simulator.draw();
}

/** @brief Forwards keyboard input to the simulator controls.
 * @see Simulator#handleKey(char, int)
 */
void keyPressed() {
  if (key==ESC) {
    key=0;
    simulator.requestRealStop();
    return;
  }
  simulator.handleKey(key, keyCode);
}

void mousePressed() { simulator.handleMouse(mouseX,mouseY); }

void exit() {
  if (simulator!=null) simulator.shutdown();
  super.exit();
}
