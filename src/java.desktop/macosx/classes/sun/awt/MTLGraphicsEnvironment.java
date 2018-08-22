package sun.awt;

import sun.java2d.MacosxSurfaceManagerFactory;
import sun.java2d.SunGraphicsEnvironment;
import sun.java2d.SurfaceManagerFactory;
import sun.lwawt.macosx.CThreading;

import java.awt.*;
import java.util.HashMap;
import java.util.Map;

/**
 * This is an implementation of a GraphicsEnvironment object for the default
 * local GraphicsEnvironment used by the Java Runtime Environment for Mac OS X
 * GUI environments.
 *
 * @see GraphicsDevice
 * @see GraphicsConfiguration
 */
public final class MTLGraphicsEnvironment extends SunGraphicsEnvironment implements ScreenEnvironment {

    /**
     * Fetch an array of all valid CoreGraphics display identifiers.
     */
    private static native int[] getDisplayIDs();

    /**
     * Fetch the CoreGraphics display ID for the 'main' display.
     */
    private static native int getMainDisplayID();

    /**
     * Noop function that just acts as an entry point for someone to force a
     * static initialization of this class.
     */
    public static void init() { }

    static {
        // Load libraries and initialize the Toolkit.
        Toolkit.getDefaultToolkit();
        // Install the correct surface manager factory.
        SurfaceManagerFactory.setInstance(new MacosxSurfaceManagerFactory());
    }

    /**
     * Register the instance with CGDisplayRegisterReconfigurationCallback().
     * The registration uses a weak global reference -- if our instance is
     * garbage collected, the reference will be dropped.
     *
     * @return Return the registration context (a pointer).
     */
    private native long registerDisplayReconfiguration();

    /**
     * Remove the instance's registration with CGDisplayRemoveReconfigurationCallback()
     */
    private native void deregisterDisplayReconfiguration(long context);

    /** Available CoreGraphics displays. */
    private final Map<Integer, MTLGraphicsDevice> devices = new HashMap<>(5);
    /**
     * The key in the {@link #devices} for the main display.
     */
    private int mainDisplayID;

    /** Reference to the display reconfiguration callback context. */
    private final long displayReconfigContext;

    /**
     * Construct a new instance.
     */
    public MTLGraphicsEnvironment() {
        if (isHeadless()) {
            displayReconfigContext = 0L;
            return;
        }

        /* Populate the device table */
        initDevices();

        /* Register our display reconfiguration listener */
        displayReconfigContext = registerDisplayReconfiguration();
        if (displayReconfigContext == 0L) {
            throw new RuntimeException("Could not register CoreGraphics display reconfiguration callback");
        }
    }

    /**
     * Called by the CoreGraphics Display Reconfiguration Callback.
     *
     * @param displayId CoreGraphics displayId
     * @param removed   true if displayId was removed, false otherwise.
     */
    @SuppressWarnings("unused")
    void _displayReconfiguration(final int displayId, final boolean removed) {
        synchronized (this) {
            // We don't need to switch to AppKit, we're already there
            mainDisplayID = getMainDisplayID();
            if (removed && devices.containsKey(displayId)) {
                final MTLGraphicsDevice gd = devices.remove(displayId);
                gd.invalidate(mainDisplayID);
                gd.displayChanged();
            }
        }
        initDevices(mainDisplayID);
    }

    @Override
    @SuppressWarnings("deprecation")
    protected void finalize() throws Throwable {
        try {
            super.finalize();
        } finally {
            deregisterDisplayReconfiguration(displayReconfigContext);
        }
    }

    /**
     * (Re)create all CGraphicsDevices, reuses a devices if it is possible.
     */
    private void initDevices(int mainDisplID) {
        synchronized (this) {
            mainDisplayID = mainDisplID;
            createDevices();
        }
        displayChanged();
    }

    private void initDevices() {
        synchronized (this) {

            // initialization of the graphics device may change
            // list of displays on hybrid systems via an activation
            // of discrete video.
            // So, we initialize the main display first, and then
            // retrieve actual list of displays.

            try {
                mainDisplayID = CThreading.privilegedExecuteOnAppKit(
                        MTLGraphicsEnvironment::getMainDisplayID);
            } catch (RuntimeException e) {
                throw e;
            } catch (Exception e) {
                throw new RuntimeException("Could not get main display ID: " +
                        e.getMessage() );
            }

            createDevices();

        }
        displayChanged();
    }

    private void createDevices() {
        final Map<Integer, MTLGraphicsDevice> old = new HashMap<>(devices);
        devices.clear();

        if (!old.containsKey(mainDisplayID)) {
            old.put(mainDisplayID, new MTLGraphicsDevice(mainDisplayID));
        }
        int[] displayIDs;
        try {
            displayIDs = CThreading.privilegedExecuteOnAppKit(
                    MTLGraphicsEnvironment::getDisplayIDs);
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new RuntimeException("Could not get display IDs: " +
                    e.getMessage());
        }

        for (final int id : displayIDs) {
            devices.put(id, old.containsKey(id) ? old.get(id)
                                                : new MTLGraphicsDevice(id));
        }
    }

    @Override
    public synchronized GraphicsDevice getDefaultScreenDevice() throws HeadlessException {
        GraphicsDevice d = devices.get(mainDisplayID);
        if (d == null) {
            // we do not expect that this may happen, the only response
            // is to re-initialize the list of devices
            initDevices();

            d = devices.get(mainDisplayID);
            if (d == null) {
                throw new AWTError("no screen devices");
            }
        }
        return d;
    }

    @Override
    public synchronized GraphicsDevice[] getScreenDevices() throws HeadlessException {
        return devices.values().toArray(new MTLGraphicsDevice[devices.values().size()]);
    }

    public synchronized GraphicsDevice getScreenDevice(int displayID) {
        return devices.get(displayID);
    }

    @Override
    protected synchronized int getNumScreens() {
        return devices.size();
    }

    @Override
    protected GraphicsDevice makeScreenDevice(int screennum) {
        throw new UnsupportedOperationException("This method is unused and should not be called in this implementation");
    }

    @Override
    public boolean isDisplayLocal() {
       return true;
    }

    static String[] sLogicalFonts = { "Serif", "SansSerif", "Monospaced", "Dialog", "DialogInput" };

    @Override
    public Font[] getAllFonts() {

        Font[] newFonts;
        Font[] superFonts = super.getAllFonts();

        int numLogical = sLogicalFonts.length;
        int numOtherFonts = superFonts.length;

        newFonts = new Font[numOtherFonts + numLogical];
        System.arraycopy(superFonts,0,newFonts,numLogical,numOtherFonts);

        for (int i = 0; i < numLogical; i++)
        {
            newFonts[i] = new Font(sLogicalFonts[i], Font.PLAIN, 1);
        }
        return newFonts;
    }

}
