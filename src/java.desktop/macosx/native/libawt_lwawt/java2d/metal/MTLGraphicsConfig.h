#ifndef MTLGraphicsConfig_h_Included
#define MTLGraphicsConfig_h_Included

#import "jni.h"
#import "MTLSurfaceDataBase.h"
#import "MTLContext.h"
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>


@interface MTLGraphicsConfigUtil : NSObject {}
+ (void) _getMTLConfigInfo: (NSMutableArray *)argValue;
@end

// REMIND: Using an NSOpenGLPixelBuffer as the scratch surface has been
// problematic thus far (seeing garbage and flickering when switching
// between an NSView and the scratch surface), so the following enables
// an alternate codepath that uses a hidden NSWindow/NSView as the scratch
// surface, for the purposes of making a context current in certain
// situations.  It appears that calling [NSOpenGLContext setView] too
// frequently contributes to the bad behavior, so we should try to avoid
// switching to the scratch surface whenever possible.

/* Do we need this if we are using all off-screen drawing ? */
#define USE_NSVIEW_FOR_SCRATCH 1

/* Uncomment to have an additional CAOGLLayer instance tied to
 * each instance, which can be used to test remoting the layer
 * to an out of process window. The additional layer is needed
 * because a layer can only be attached to one context (view/window).
 * This is only for testing purposes and can be removed if/when no
 * longer needed.
 */


/**
 * The MTLGraphicsConfigInfo structure contains information specific to a
 * given CGLGraphicsConfig (pixel format).
 *
 *     jint screen;
 * The screen and PixelFormat for the associated CGLGraphicsConfig.
 *
 *     NSOpenGLPixelFormat *pixfmt;
 * The pixel format of the native NSOpenGL context.
 *
 *     OGLContext *context;
 * The context associated with this CGLGraphicsConfig.
 */
typedef struct _MTLGraphicsConfigInfo {
    jint                screen;
    NSOpenGLPixelFormat *pixfmt;
    MTLContext          *context;
} MTLGraphicsConfigInfo;

/**
 */
typedef struct _MTLCtxInfo {
    id<MTLDevice>       mtlDevice;
    NSView              *scratchSurface;
} MTLCtxInfo;

#endif /* MTLGraphicsConfig_h_Included */
