/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */
#include "Rendering/GL/MacEGLBridge.h"
#include "glad/glad.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <dlfcn.h>
#include <filesystem>
#include <vector>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

@interface SharingTestLayer : CAMetalLayer
@property(nonatomic, strong) id<CAMetalDrawable> capturedDrawable;
@end

@implementation SharingTestLayer
- (id<CAMetalDrawable>)nextDrawable
{
	id<CAMetalDrawable> drawable = [super nextDrawable];
	self.capturedDrawable = drawable;
	return drawable;
}
@end

int main(int argc, char** argv)
{
	assert(argc == 2);
	const auto prefix = std::filesystem::absolute(argv[1]);
	setenv("GALLIUM_DRIVER", "zink", 1);
	setenv("MESA_GL_VERSION_OVERRIDE", "4.6COMPAT", 1);
	setenv("MESA_GLSL_VERSION_OVERRIDE", "460", 1);
	setenv("VK_DRIVER_FILES", (prefix / "share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json").c_str(), 1);
	void* eglLibrary = dlopen((prefix / "lib/libEGL.1.dylib").c_str(), RTLD_NOW | RTLD_LOCAL);
	if (!eglLibrary) { std::fprintf(stderr, "%s\n", dlerror()); return 1; }
#define EGL_FUNCTION(name, type) auto name = reinterpret_cast<type>(dlsym(eglLibrary, #name)); assert(name)
	EGL_FUNCTION(eglGetProcAddress, PFNEGLGETPROCADDRESSPROC);
	EGL_FUNCTION(eglInitialize, PFNEGLINITIALIZEPROC);
	EGL_FUNCTION(eglBindAPI, PFNEGLBINDAPIPROC);
	EGL_FUNCTION(eglChooseConfig, PFNEGLCHOOSECONFIGPROC);
	EGL_FUNCTION(eglCreatePbufferSurface, PFNEGLCREATEPBUFFERSURFACEPROC);
	EGL_FUNCTION(eglCreateContext, PFNEGLCREATECONTEXTPROC);
	EGL_FUNCTION(eglMakeCurrent, PFNEGLMAKECURRENTPROC);
	EGL_FUNCTION(eglDestroyContext, PFNEGLDESTROYCONTEXTPROC);
	EGL_FUNCTION(eglDestroySurface, PFNEGLDESTROYSURFACEPROC);
	EGL_FUNCTION(eglTerminate, PFNEGLTERMINATEPROC);
#undef EGL_FUNCTION
	auto getDisplay = reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(eglGetProcAddress("eglGetPlatformDisplayEXT"));
	assert(getDisplay);
	EGLDisplay display = getDisplay(EGL_PLATFORM_SURFACELESS_MESA, nullptr, nullptr);
	assert(display && eglInitialize(display, nullptr, nullptr) && eglBindAPI(EGL_OPENGL_API));
	const EGLint attributes[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
	EGLConfig config;
	EGLint count;
	assert(eglChooseConfig(display, attributes, &config, 1, &count) && count);
	const EGLint dimensions[] = {EGL_WIDTH, 32, EGL_HEIGHT, 32, EGL_NONE};
	EGLSurface surface = eglCreatePbufferSurface(display, config, dimensions);
	const EGLint contextAttributes[] = {EGL_CONTEXT_MAJOR_VERSION_KHR, 4, EGL_CONTEXT_MINOR_VERSION_KHR, 6, EGL_NONE};
	EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttributes);
	assert(surface && context && eglMakeCurrent(display, surface, surface, context));
	assert(gladLoadGLLoader(reinterpret_cast<GLADloadproc>(eglGetProcAddress)));
	void* driver = dlopen((prefix / "lib/libvulkan_kosmickrisp.dylib").c_str(), RTLD_NOW | RTLD_LOCAL | RTLD_NOLOAD);
	assert(driver);
	auto getImage = reinterpret_cast<bool (*)(void**, uint64_t*)>(dlsym(eglLibrary, "recoil_mesa_get_vk_color_buffer_v1"));
	auto getTexture = reinterpret_cast<bool (*)(void*, uint64_t, void**, void**)>(dlsym(driver, "recoil_kk_get_metal_texture_v1"));
	assert(getImage && getTexture);
	auto nativeTexture = [&]() {
		void* vkDevice = nullptr;
		uint64_t image = 0;
		void* device = nullptr;
		void* texture = nullptr;
		assert(getImage(&vkDevice, &image) && getTexture(vkDevice, image, &device, &texture));
		return std::pair(device, texture);
	};
	for (int pass = 0; pass < 2; ++pass) {
		for (int width : {64, 127, 96}) {
			const int height = width / 2 + 1;
			GLuint sourceFBO, sourceColor, outputFBO, outputColor;
			glGenFramebuffers(1, &sourceFBO);
			glGenRenderbuffers(1, &sourceColor);
			glBindRenderbuffer(GL_RENDERBUFFER, sourceColor);
			glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, width, height);
			glBindFramebuffer(GL_FRAMEBUFFER, sourceFBO);
			glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, sourceColor);
			assert(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
			glGenFramebuffers(1, &outputFBO);
			glGenTextures(1, &outputColor);
			glBindTexture(GL_TEXTURE_2D, outputColor);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width * 2, height * 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
			glBindFramebuffer(GL_FRAMEBUFFER, outputFBO);
			glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, outputColor, 0);
			assert(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
			for (int frame = 0; frame < 5; ++frame) {
				glBindFramebuffer(GL_FRAMEBUFFER, sourceFBO);
				glDisable(GL_SCISSOR_TEST);
				const int red = 160 + frame * 10;
				glClearColor(red / 255.0f, 80 / 255.0f, 30 / 255.0f, 1);
				glClear(GL_COLOR_BUFFER_BIT);
				if (frame != 4) {
					glEnable(GL_SCISSOR_TEST);
					glScissor(0, height / 2, width, height - height / 2);
					glClearColor(30 / 255.0f, 80 / 255.0f, red / 255.0f, 1);
					glClear(GL_COLOR_BUFFER_BIT);
				}
				glDisable(GL_SCISSOR_TEST);
				glFinish();
				auto [device, source] = nativeTexture();
				glBindFramebuffer(GL_READ_FRAMEBUFFER, outputFBO);
				auto [outputDevice, output] = nativeTexture();
				assert(device == outputDevice);
				if (!MacMetalFX::UpscaleShared(device, source, output)) {
					std::fprintf(stderr, "Shared MetalFX failed: %s\n", MacMetalFX::GetError());
					return 1;
				}
				std::vector<unsigned char> pixels(width * height * 16);
				// Readback is only an assertion here; the scaler itself shares GPU textures.
				glReadPixels(0, 0, width * 2, height * 2, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
				for (int y : {height / 2, height * 3 / 2}) {
					const int offset = (y * width * 2 + width) * 4;
					assert(std::abs(int(pixels[offset]) - (y < height || frame == 4 ? red : 30)) < 5);
					assert(std::abs(int(pixels[offset + 1]) - 80) < 5);
					assert(std::abs(int(pixels[offset + 2]) - (y < height || frame == 4 ? 30 : red)) < 5);
				}
				// Exercise GL's GPU consumer path, as used to composite the world.
				glBindFramebuffer(GL_DRAW_FRAMEBUFFER, sourceFBO);
				glBlitFramebuffer(0, 0, width * 2, height * 2, 0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_NEAREST);
				glBindFramebuffer(GL_READ_FRAMEBUFFER, sourceFBO);
				unsigned char sample[4];
				glReadPixels(width / 2, height / 4, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, sample);
				assert(std::abs(int(sample[0]) - red) < 5 && std::abs(int(sample[2]) - 30) < 5);
				assert(glGetError() == GL_NO_ERROR);
			}
			glBindFramebuffer(GL_FRAMEBUFFER, 0);
			glDeleteFramebuffers(1, &sourceFBO);
			glDeleteFramebuffers(1, &outputFBO);
			glDeleteRenderbuffers(1, &sourceColor);
			glDeleteTextures(1, &outputColor);
		}
		MacMetalFX::Destroy();
	}
	glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
	glReadBuffer(GL_BACK);
	glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
	glDisable(GL_SCISSOR_TEST);
	glClearColor(1, 0, 0, 1);
	glClear(GL_COLOR_BUFFER_BIT);
	glEnable(GL_SCISSOR_TEST);
	glScissor(0, 16, 32, 16);
	glClearColor(0, 0, 1, 1);
	glClear(GL_COLOR_BUFFER_BIT);
	glDisable(GL_SCISSOR_TEST);
	glFinish();
	auto [device, image] = nativeTexture();
	@autoreleasepool {
		SharingTestLayer* layer = [SharingTestLayer layer];
		layer.device = (__bridge id<MTLDevice>)device;
		layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
		layer.drawableSize = CGSizeMake(32, 32);
		layer.framebufferOnly = NO;
		if (!MacMetalFX::PresentShared(device, image, (__bridge void*)layer)) {
			std::fprintf(stderr, "Shared presentation failed: %s\n", MacMetalFX::GetError());
			return 1;
		}
		assert(layer.capturedDrawable);
		id<MTLDevice> metalDevice = layer.device;
		id<MTLCommandQueue> queue = [metalDevice newCommandQueue];
		id<MTLBuffer> pixels = [metalDevice newBufferWithLength:32 * 256 options:MTLResourceStorageModeShared];
		id<MTLCommandBuffer> commands = [queue commandBuffer];
		id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
		[blit copyFromTexture:layer.capturedDrawable.texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
			sourceSize:MTLSizeMake(32, 32, 1) toBuffer:pixels destinationOffset:0
			destinationBytesPerRow:256 destinationBytesPerImage:32 * 256];
		[blit endEncoding];
		[commands commit];
		[commands waitUntilCompleted];
		assert(commands.status == MTLCommandBufferStatusCompleted);
		const auto* bytes = static_cast<const unsigned char*>(pixels.contents);
		// Drawable bytes are top-first BGRA. GL's blue top must appear at the top.
		assert(bytes[8 * 256 + 16 * 4] > 250 && bytes[8 * 256 + 16 * 4 + 2] < 5);
		assert(bytes[24 * 256 + 16 * 4] < 5 && bytes[24 * 256 + 16 * 4 + 2] > 250);
		MacMetalFX::Destroy();
	}
	eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	eglDestroyContext(display, context);
	eglDestroySurface(display, surface);
	eglTerminate(display);
	std::puts("PASS: Mesa/MetalFX GPU sharing, repeated writes, resize, color, orientation, cleanup and presentation export");
}
