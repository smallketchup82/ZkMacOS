/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */
// Compile with Mac/WindowManagerHelper.cpp, SDL2 and AppKit. Pass "custom" to cover the notch.
#import <AppKit/AppKit.h>
#include <SDL.h>
#include <SDL_syswm.h>
#include <cassert>
#include <cstdio>
#include <cstring>
#include "System/Platform/WindowManagerHelper.h"

int main(int argc, char** argv)
{
	@autoreleasepool {
		const bool custom = argc > 1 && std::strcmp(argv[1], "custom") == 0;
		SDL_SetHint(SDL_HINT_VIDEO_MAC_FULLSCREEN_SPACES, custom ? "0" : "1");
		assert(SDL_Init(SDL_INIT_VIDEO) == 0);
		SDL_Window* window = SDL_CreateWindow("Zero-K fullscreen coverage check", 100, 100, 800, 600,
			SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
		assert(window);
		double left, right, height;
		assert(!WindowManagerHelper::GetMacNotchGeometry(window, left, right, height));
		assert(SDL_SetWindowFullscreen(window, SDL_WINDOW_FULLSCREEN_DESKTOP) == 0);
		SDL_PumpEvents();
		SDL_SysWMinfo info = {};
		SDL_VERSION(&info.version);
		assert(SDL_GetWindowWMInfo(window, &info));
		NSWindow* nativeWindow = info.info.cocoa.window;
		const bool hasNotch = nativeWindow.screen.auxiliaryTopLeftArea.size.width > 0;
		const bool covered = WindowManagerHelper::GetMacNotchGeometry(window, left, right, height);
		assert(covered == (custom && hasNotch));
		if (covered) {
			assert(right > left && height > 0);
			std::printf("PASS: native notch-covering fullscreen, notch=%.1f points wide, %.1f high, gap=%.1f\n", right-left, height, right-left+15);
		} else {
			std::printf("PASS: %s fullscreen uses the default layout\n", custom ? "non-notched display" : "below-notch Spaces");
		}
		assert(SDL_SetWindowFullscreen(window, 0) == 0);
		assert(!WindowManagerHelper::GetMacNotchGeometry(window, left, right, height));
		SDL_DestroyWindow(window);
		SDL_Quit();
	}
}
