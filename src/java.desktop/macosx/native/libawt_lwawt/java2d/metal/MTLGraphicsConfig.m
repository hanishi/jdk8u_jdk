/*
 * Copyright (c) 2011, 2015, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

#import "sun_java2d_metal_MTLGraphicsConfig.h"

#import "MTLGraphicsConfig.h"
#import "MTLSurfaceData.h"
#import "ThreadUtilities.h"

#import <stdlib.h>
#import <string.h>
#import <ApplicationServices/ApplicationServices.h>
#import <JavaNativeFoundation/JavaNativeFoundation.h>

#pragma mark -
#pragma mark "--- Mac OS X specific methods for GL pipeline ---"

/**
 * Disposes all memory and resources associated with the given
 * CGLGraphicsConfigInfo (including its native MTLContext data).
 */
void
MTLGC_DestroyMTLGraphicsConfig(jlong pConfigInfo)
{
    J2dTraceLn(J2D_TRACE_INFO, "MTLGC_DestroyMTLGraphicsConfig");

    MTLGraphicsConfigInfo *mtlinfo =
        (MTLGraphicsConfigInfo *)jlong_to_ptr(pConfigInfo);
    if (mtlinfo == NULL) {
        J2dRlsTraceLn(J2D_TRACE_ERROR,
                      "MTLGC_DestroyMTLGraphicsConfig: info is null");
        return;
    }


    MTLContext *oglc = (MTLContext*)mtlinfo->context;
    if (oglc != NULL) {
        MTLContext_DestroyContextResources(oglc);

        MTLCtxInfo *ctxinfo = (MTLCtxInfo *)oglc->ctxInfo;
        if (ctxinfo != NULL) {
            NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
            [ctxinfo->mtlDevice release];
            if (ctxinfo->scratchSurface != 0) {
                [ctxinfo->scratchSurface release];
            }
            [pool drain];
            free(ctxinfo);
            oglc->ctxInfo = NULL;
        }
        mtlinfo->context = NULL;
    }
    free(mtlinfo);
}

#pragma mark -
#pragma mark "--- MTLGraphicsConfig methods ---"


/**
 * Attempts to initialize CGL and the core OpenGL library.
 */
JNIEXPORT jboolean JNICALL
Java_sun_java2d_metal_MTLGraphicsConfig_initMTL
    (JNIEnv *env, jclass cglgc)
{
    J2dRlsTraceLn(J2D_TRACE_INFO, "MTLGraphicsConfig_initMTL");

    if (!MTLFuncs_OpenLibrary()) {
        return JNI_FALSE;
    }

    if (!MTLFuncs_InitPlatformFuncs() ||
        !MTLFuncs_InitBaseFuncs() ||
        !MTLFuncs_InitExtFuncs())
    {
        MTLFuncs_CloseLibrary();
        return JNI_FALSE;
    }

    return JNI_TRUE;
}


/**
 * Determines whether the CGL pipeline can be used for a given GraphicsConfig
 * provided its screen number and visual ID.  If the minimum requirements are
 * met, the native CGLGraphicsConfigInfo structure is initialized for this
 * GraphicsConfig with the necessary information (pixel format, etc.)
 * and a pointer to this structure is returned as a jlong.  If
 * initialization fails at any point, zero is returned, indicating that CGL
 * cannot be used for this GraphicsConfig (we should fallback on an existing
 * 2D pipeline).
 */
JNIEXPORT jlong JNICALL
Java_sun_java2d_metal_MTLGraphicsConfig_getMTLConfigInfo
    (JNIEnv *env, jclass cglgc, jint displayID)
{
  jlong ret = 0L;
  JNF_COCOA_ENTER(env);
  NSMutableArray * retArray = [NSMutableArray arrayWithCapacity:3];
  [retArray addObject: [NSNumber numberWithInt: (int)displayID]];
  if ([NSThread isMainThread]) {
      [MTLGraphicsConfigUtil _getMTLConfigInfo: retArray];
  } else {
      [MTLGraphicsConfigUtil performSelectorOnMainThread: @selector(_getMTLConfigInfo:) withObject: retArray waitUntilDone: YES];
  }
  NSNumber * num = (NSNumber *)[retArray objectAtIndex: 0];
  ret = (jlong)[num longValue];
  JNF_COCOA_EXIT(env);
  return ret;
}



@implementation MTLGraphicsConfigUtil
+ (void) _getMTLConfigInfo: (NSMutableArray *)argValue {
    AWT_ASSERT_APPKIT_THREAD;

    jint displayID = (jint)[(NSNumber *)[argValue objectAtIndex: 0] intValue];
    JNIEnv *env = [ThreadUtilities getJNIEnvUncached];
    [argValue removeAllObjects];

    J2dRlsTraceLn(J2D_TRACE_INFO, "MTLGraphicsConfig_getMTLConfigInfo");

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];


    NSRect contentRect = NSMakeRect(0, 0, 64, 64);
    NSWindow *window =
        [[NSWindow alloc]
            initWithContentRect: contentRect
            styleMask: NSBorderlessWindowMask
            backing: NSBackingStoreBuffered
            defer: false];
    if (window == nil) {
        J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGraphicsConfig_getMTLConfigInfo: NSWindow is NULL");
        [argValue addObject: [NSNumber numberWithLong: 0L]];
        return;
    }

    NSView *scratchSurface =
        [[NSView alloc]
            initWithFrame: contentRect];
    if (scratchSurface == nil) {
        J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGraphicsConfig_getMTLConfigInfo: NSView is NULL");
        [argValue addObject: [NSNumber numberWithLong: 0L]];
        return;
    }
    fprintf(stderr, "USE_NSVIEW_FOR_SCRATCH");
    [window setContentView: scratchSurface];

    jint caps = CAPS_EMPTY;
    MTLContext_GetExtensionInfo(env, &caps);

    caps |= CAPS_DOUBLEBUFFERED;

    J2dRlsTraceLn1(J2D_TRACE_INFO,
                   "MTLGraphicsConfig_getMTLConfigInfo: db=%d",
                   (caps & CAPS_DOUBLEBUFFERED) != 0);

    MTLCtxInfo *ctxinfo = (MTLCtxInfo *)malloc(sizeof(MTLCtxInfo));
    if (ctxinfo == NULL) {
        J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGC_InitMTLContext: could not allocate memory for ctxinfo");
        [NSOpenGLContext clearCurrentContext];
        [argValue addObject: [NSNumber numberWithLong: 0L]];
        return;
    }
    memset(ctxinfo, 0, sizeof(MTLCtxInfo));
    ctxinfo->scratchSurface = scratchSurface;
    ctxinfo->mtlDevice = CGDirectDisplayCopyCurrentMetalDevice(displayID);

    MTLContext *mtlc = (MTLContext *)malloc(sizeof(MTLContext));
    if (mtlc == 0L) {
        J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGC_InitMTLContext: could not allocate memory for mtlc");
        [NSOpenGLContext clearCurrentContext];
        free(ctxinfo);
        [argValue addObject: [NSNumber numberWithLong: 0L]];
        return;
    }
    memset(mtlc, 0, sizeof(MTLContext));
    mtlc->ctxInfo = ctxinfo;
    mtlc->caps = caps;

    // create the MTLGraphicsConfigInfo record for this config
    MTLGraphicsConfigInfo *mtlinfo = (MTLGraphicsConfigInfo *)malloc(sizeof(MTLGraphicsConfigInfo));
    if (mtlinfo == NULL) {
        J2dRlsTraceLn(J2D_TRACE_ERROR, "MTLGraphicsConfig_getMTLConfigInfo: could not allocate memory for mtlinfo");
        [NSOpenGLContext clearCurrentContext];
        free(mtlc);
        free(ctxinfo);
        [argValue addObject: [NSNumber numberWithLong: 0L]];
        return;
    }
    memset(mtlinfo, 0, sizeof(MTLGraphicsConfigInfo));
    mtlinfo->screen = displayID;
    mtlinfo->context = mtlc;

  //  [NSOpenGLContext clearCurrentContext];
    [argValue addObject: [NSNumber numberWithLong:ptr_to_jlong(mtlinfo)]];
    [pool drain];
}
@end //GraphicsConfigUtil

JNIEXPORT jint JNICALL
Java_sun_java2d_metal_MTLGraphicsConfig_getMTLCapabilities
    (JNIEnv *env, jclass mtlgc, jlong configInfo)
{
    J2dTraceLn(J2D_TRACE_INFO, "MTLGraphicsConfig_getMTLCapabilities");

    MTLGraphicsConfigInfo *mtlinfo =
        (MTLGraphicsConfigInfo *)jlong_to_ptr(configInfo);
    if ((mtlinfo == NULL) || (mtlinfo->context == NULL)) {
        return CAPS_EMPTY;
    } else {
        return mtlinfo->context->caps;
    }
}

JNIEXPORT jint JNICALL
Java_sun_java2d_metal_MTLGraphicsConfig_nativeGetMaxTextureSize
    (JNIEnv *env, jclass mtlgc)
{
    J2dTraceLn(J2D_TRACE_INFO, "MTLGraphicsConfig_nativeGetMaxTextureSize");

    __block int max = 0;

//    [ThreadUtilities performOnMainThreadWaiting:YES block:^(){
//    }];

    return (jint)max;
}
