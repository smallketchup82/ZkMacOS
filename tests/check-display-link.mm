/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */
#include "Rendering/GL/MacEGLBridge.h"
#include <cassert>
#include <cstdio>
#include <vector>
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

int main()
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 640, 400)
			styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
			backing:NSBackingStoreBuffered defer:NO];
		window.releasedWhenClosed = NO;
		window.title = @"Zero-K display-link probe";
		CAMetalLayer* layer = [CAMetalLayer layer];
		layer.device = MTLCreateSystemDefaultDevice();
		layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
		layer.drawableSize = CGSizeMake(640, 400);
		window.contentView.wantsLayer = YES;
		window.contentView.layer = layer;
		[window makeKeyAndOrderFront:nil];
		[NSApp activateIgnoringOtherApps:YES];
		std::vector<unsigned char> pixels(640 * 400 * 4, 128);
		MTLTextureDescriptor* description = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:640 height:400 mipmapped:NO];
		description.storageMode = MTLStorageModeShared;
		id<MTLTexture> source = [layer.device newTextureWithDescriptor:description];
		[source replaceRegion:MTLRegionMake2D(0, 0, 640, 400) mipmapLevel:0 withBytes:pixels.data() bytesPerRow:640 * 4];
		for (int pass = 0; pass < 3; ++pass) {
			int updates = 0;
			for (int frame = 0; frame < 12; ++frame) {
				// An unknown SDL refresh rate must restore the system default range.
				updates += MacMetalFX::WaitForFrame((__bridge void*)layer, frame == 6 ? 0 : 120);
				if (pass == 1)
					assert(MacMetalFX::PresentPixels(pixels.data(), 640, 400, (__bridge void*)layer));
				else
					assert(MacMetalFX::PresentShared((__bridge void*)layer.device, (__bridge void*)source, (__bridge void*)layer));
			}
			// Callback cadence depends on occlusion, display rate and system load.
			assert(updates > 0);
			// The callback must not trap the main thread when there is no drawable.
			[window miniaturize:nil];
			const CFTimeInterval start = CACurrentMediaTime();
			assert(!MacMetalFX::WaitForFrame((__bridge void*)layer, 120, false));
			assert(CACurrentMediaTime() - start < 0.25);
			[window deminiaturize:nil];
			[window setContentSize:NSMakeSize(641 + pass, 401 + pass)];
			layer.drawableSize = CGSizeMake(641 + pass, 401 + pass);
			MacMetalFX::StopDisplayLink();
			// Also exercise legacy presentation after invalidating the link.
			assert(MacMetalFX::PresentShared((__bridge void*)layer.device, (__bridge void*)source, (__bridge void*)layer));
		}
		MacMetalFX::StopDisplayLink();
		MacMetalFX::Destroy();
		[window close];
		std::puts("PASS: display-link callbacks, shared and uploaded presentation, bounded hidden-window wait, resize, disable and recreation");
	}
}
