/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */
// Run using the compile command at https://github.com/smallketchup82/ZkMacOS/wiki/Development-Rendering-MetalFX.
#include "Rendering/GL/MacEGLBridge.h"

#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>

int main()
{
	const void* output = nullptr;
	int rowLength = 0;
	assert(!MacMetalFX::Upscale(nullptr, 0, 0, 0, 0, output, rowLength));
	for (int pass = 0; pass < 2; ++pass) {
		for (int width : {64, 127, 96}) {
			const int height = width / 2 + 1;
			std::vector<unsigned char> pixels(width * height * 4);
			for (int y = 0; y < height; ++y) {
				for (int x = 0; x < width; ++x) {
					const int offset = (y * width + x) * 4;
					pixels[offset] = y < height / 2 ? 200 : 30;
					pixels[offset + 1] = 80;
					pixels[offset + 2] = y < height / 2 ? 30 : 200;
					pixels[offset + 3] = 255;
				}
			}
			assert(!MacMetalFX::Upscale(pixels.data(), width, height, width - 1, height, output, rowLength));
			if (!MacMetalFX::Upscale(pixels.data(), width, height, width * 2, height * 2, output, rowLength)) {
				std::fprintf(stderr, "MetalFX failed: %s\n", MacMetalFX::GetError());
				return 1;
			}
			assert(output && rowLength >= width * 2 && rowLength % 64 == 0);
			const auto* result = static_cast<const unsigned char*>(output);
			// Interior values retain perceptual color and row order. Do not assert
			// edges: MetalFX deliberately sharpens those and can overshoot.
			for (int y : {height / 2, height * 3 / 2}) {
				const int offset = (y * rowLength + width) * 4;
				assert(std::abs(int(result[offset]) - (y < height ? 200 : 30)) < 5);
				assert(std::abs(int(result[offset + 1]) - 80) < 5);
				assert(std::abs(int(result[offset + 2]) - (y < height ? 30 : 200)) < 5);
			}
		}
		MacMetalFX::Destroy();
	}
	std::puts("PASS: real MetalFX GPU scaling, odd sizes, row stride, color, orientation, resizing and recreation");
}
