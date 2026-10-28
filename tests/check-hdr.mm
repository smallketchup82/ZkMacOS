/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */
// Native macOS HDR regression checks, OpenAI Codex assisted.
#include "Rendering/GL/MacEGLBridge.h"
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

@interface HDRTestLayer : CAMetalLayer
@property(nonatomic, strong) id<CAMetalDrawable> capturedDrawable;
@end
@implementation HDRTestLayer
- (id<CAMetalDrawable>)nextDrawable
{
	self.capturedDrawable = [super nextDrawable];
	return self.capturedDrawable;
}
@end

int main()
{
	@autoreleasepool {
		id<MTLDevice> device = MTLCreateSystemDefaultDevice();
		assert(device);
		for (bool spatial : {false, true}) for (int width : {64, 127, 80}) {
			const int height = width / 2 + 1;
			auto texture = [&](int w, int h) {
				MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
					MTLPixelFormatRGBA16Float width:w height:h mipmapped:NO];
				desc.storageMode = MTLStorageModeShared;
				desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
				return [device newTextureWithDescriptor:desc];
			};
			id<MTLTexture> source = texture(width, height);
			id<MTLTexture> output = texture(width * 2, height * 2);
			assert(source && output);
			std::vector<__fp16> pixels(width * height * 4, 0.0);
			for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
				const int i = (y * width + x) * 4;
				const bool bright = x >= width / 2 && x < width * 3 / 4 && y >= height / 3 && y < height * 2 / 3;
				const bool superwhite = x > width * 7 / 8;
				pixels[i] = superwhite ? 2.0 : bright ? 1.0 : 0.25;
				pixels[i+1] = bright ? 0.8 : 0.25;
				pixels[i+2] = 0.25;
				pixels[i+3] = 1.0;
			}
			[source replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:pixels.data() bytesPerRow:width * 8];
			if (spatial && !MacMetalFX::UpscaleShared((__bridge void*)device, (__bridge void*)source, (__bridge void*)output)) {
				std::fprintf(stderr, "HDR failed: %s\n", MacMetalFX::GetError()); return 1;
			}
			if (!spatial) {
				// Keep the same reference colors when MetalFX is disabled.
				std::vector<__fp16> doubled(width * height * 16);
				for (int y = 0; y < height * 2; ++y) for (int x = 0; x < width * 2; ++x)
					for (int c = 0; c < 4; ++c) doubled[(y * width * 2 + x) * 4 + c] = pixels[((y / 2) * width + x / 2) * 4 + c];
				[output replaceRegion:MTLRegionMake2D(0, 0, width * 2, height * 2) mipmapLevel:0 withBytes:doubled.data() bytesPerRow:width * 16];
			}
			std::vector<__fp16> result(width * height * 16);
			[output getBytes:result.data() bytesPerRow:width * 16 fromRegion:MTLRegionMake2D(0, 0, width * 2, height * 2) mipmapLevel:0];
			auto sample = [&](int x, int y, int c) { return float(result[(y * width * 2 + x) * 4 + c]); };
			assert(std::abs(sample(width / 4, height, 0) - 0.25f) < 0.005f); // No added exposure or color grading.
			assert(std::abs(sample(width * 5 / 4, height, 0) - 1.0f) < 0.01f); // SDR white is not expanded.
			assert(std::abs(sample(width * 15 / 8, height, 0) - 2.0f) < 0.01f); // The game's superwhite energy survives.
			assert(sample(width * 5 / 4, height, 0) > sample(width * 5 / 4, height, 1)); // Hue survives.
			assert(std::abs(sample(width / 4, height / 4, 0) - 0.25f) < 0.005f); // No additional bloom.
			// Simulate opaque legacy UI drawing into the float composition target.
			std::vector<__fp16> white(8 * 8 * 4, 1.0);
			[output replaceRegion:MTLRegionMake2D(0, 0, 8, 8) mipmapLevel:0 withBytes:white.data() bytesPerRow:8 * 8];
			HDRTestLayer* layer = [HDRTestLayer layer];
			layer.device = device;
			layer.pixelFormat = MTLPixelFormatRGBA16Float;
			layer.drawableSize = CGSizeMake(width * 2, height * 2);
			layer.framebufferOnly = NO;
			for (float headroom : {4.0f, 1.0f, 2.0f}) {
				assert(MacMetalFX::PresentShared((__bridge void*)device, (__bridge void*)output, (__bridge void*)layer, headroom));
				assert(layer.capturedDrawable);
				const NSUInteger rowBytes = (width * 16 + 255) & ~NSUInteger(255);
				id<MTLBuffer> buffer = [device newBufferWithLength:rowBytes * height * 2 options:MTLResourceStorageModeShared];
				id<MTLCommandBuffer> commands = [[device newCommandQueue] commandBuffer];
				id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
				[blit copyFromTexture:layer.capturedDrawable.texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
					sourceSize:MTLSizeMake(width * 2, height * 2, 1) toBuffer:buffer destinationOffset:0
					destinationBytesPerRow:rowBytes destinationBytesPerImage:rowBytes * height * 2];
				[blit endEncoding]; [commands commit]; [commands waitUntilCompleted];
				assert(commands.status == MTLCommandBufferStatusCompleted);
				const auto* bytes = static_cast<const __fp16*>(buffer.contents);
				assert(std::abs(float(bytes[(height * 2 - 1) * rowBytes / 2]) - 1.0f) < 0.005f); // UI white is always SDR white.
				const float highlight = bytes[height * rowBytes / 2 + (width * 15 / 8) * 4];
				assert(highlight <= headroom + 0.005f && highlight >= 0.99f);
				if (headroom > 1.0f) assert(highlight > 1.2f);
				layer.capturedDrawable = nil;
			}
		}
		MacMetalFX::Destroy();
		// Exercise real display capability gating and reversible layer configuration.
		[NSApplication sharedApplication];
		NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 200)
			styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
		CAMetalLayer* layer = [CAMetalLayer layer];
		layer.device = device;
		layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
		const bool supported = window.screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0;
		assert(MacMetalFX::ConfigureHDR((__bridge void*)layer, (__bridge void*)window, true) == supported);
		assert(layer.wantsExtendedDynamicRangeContent == supported);
		if (supported) assert(layer.pixelFormat == MTLPixelFormatRGBA16Float && layer.colorspace);
		assert(MacMetalFX::HDRHeadroom((__bridge void*)window) >= 1.0f);
		MacMetalFX::ConfigureHDR((__bridge void*)layer, (__bridge void*)window, false);
		assert(!layer.wantsExtendedDynamicRangeContent && layer.pixelFormat == MTLPixelFormatBGRA8Unorm);
		MacMetalFX::Destroy();
		std::puts("PASS: unchanged SDR colors, original superwhite energy, no artificial highlight expansion, SDR UI, headroom changes, MetalFX, resize and SDR restoration");
	}
}
