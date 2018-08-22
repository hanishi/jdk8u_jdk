package sun.awt;

import java.awt.*;

public interface ScaledDevice {
    int getScaleFactor();
    double getXResolution();
    double getYResolution();
    Insets getScreenInsets();
    int getDisplayID();

    Rectangle getDefaultBounds();
}
