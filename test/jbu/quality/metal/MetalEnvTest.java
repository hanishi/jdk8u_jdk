package quality.metal;

import org.junit.Test;

import java.awt.*;
import java.awt.image.BufferedImage;

public class MetalEnvTest {

    @Test
    public void testGE() throws Exception {
        GraphicsEnvironment ge = GraphicsEnvironment.getLocalGraphicsEnvironment();
        GraphicsDevice[] devices = ge.getScreenDevices();
        GraphicsDevice d = ge.getDefaultScreenDevice();

        BufferedImage bi = d.getConfigurations()[0].createCompatibleImage(1000, 1000);
        bi.createGraphics().fillOval(0, 0, 100, 100);
    }

    @Test
    public void testMetal1() throws Exception {
    }
    @Test
    public void testMetal2() throws Exception {
    }
}
