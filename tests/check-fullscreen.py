"""Exercise the patched engine methods; --native also opens a short SDL/Cocoa probe."""
from pathlib import Path
import argparse
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--native', action='store_true')
args = parser.parse_args()
source = (root / 'external/recoil/rts/Rendering/GlobalRendering.cpp').read_text()


def function(signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


methods = '\n'.join(function(name) for name in (
    'static uint32_t GetFullScreenFlag(', 'static bool IsBorderlessFullScreen(',
    'void CGlobalRendering::SetWindowAttributes(', 'void CGlobalRendering::SaveWindowPosAndSize(',
))
harness = r'''
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <map>
#include <string>
#include <vector>
#ifdef NATIVE_FULLSCREEN_TEST
#include <SDL.h>
#else
constexpr uint32_t SDL_WINDOW_FULLSCREEN = 1, SDL_WINDOW_FULLSCREEN_DESKTOP = 0x1001, SDL_WINDOW_MINIMIZED = 0x40;
constexpr int SDL_FALSE = 0, SDL_TRUE = 1;
struct SDL_Window { uint32_t flags = 0; };
struct SDL_Rect { int x, y, w, h; };
std::vector<std::string> calls;
bool failFullscreen = false;
int SDL_GetNumVideoDisplays() { return 2; }
int SDL_GetDisplayBounds(int index, SDL_Rect* r) { *r = {index ? -1920 : 0, 0, 1920, 1080}; return 0; }
uint32_t SDL_GetWindowFlags(SDL_Window* w) { return w->flags; }
int SDL_SetWindowFullscreen(SDL_Window* w, uint32_t flags) {
    calls.push_back(flags ? "enter" : "exit");
    if (failFullscreen) return -1;
    w->flags = flags;
    return 0;
}
const char* SDL_GetError() { return "test failure"; }
void SDL_RestoreWindow(SDL_Window*) { calls.push_back("restore"); }
void SDL_SetWindowMinimumSize(SDL_Window*, int, int) {}
void SDL_SetWindowPosition(SDL_Window*, int, int) { calls.push_back("position"); }
void SDL_SetWindowSize(SDL_Window*, int, int) { calls.push_back("size"); }
void SDL_SetWindowBordered(SDL_Window*, int) { calls.push_back("border"); }
void SDL_MaximizeWindow(SDL_Window*) { calls.push_back("maximize"); }
#endif
namespace WindowManagerHelper { void SetWindowResizable(SDL_Window*, bool) {} }
#define LOG(...) ((void)0)
#define LOG_L(...) ((void)0)
struct int2 { int x, y; bool operator==(const int2&) const = default; };
struct Config {
    std::map<std::string, int> values;
    bool GetBool(const char* key) { return values[key]; }
    int GetInt(const char* key) { return values[key]; }
    void Set(const char* key, int value, bool, bool) { values[key] = value; }
} config, *configHandler = &config;
struct CGlobalRendering {
    bool borderless = false, fullScreen = false;
    int winPosX = 100, winPosY = 100, winSizeX = 800, winSizeY = 600, numDisplays = 1;
    int2 minRes = {400, 300};
    SDL_Window* sdlWindow;
    int2 GetMaxWinRes() const { return {1920, 1080}; }
    int2 GetCfgWinRes() const { return {config.values["width"], config.values["height"]}; }
    void GetWindowPosSizeBounded(int&, int&, int&, int&) const {}
    void SetWindowAttributes(SDL_Window*);
    void SaveWindowPosAndSize();
};
'''
checks = r'''
int main() {
    config.values = {{"WindowPosX",100}, {"WindowPosY",100}, {"width",800}, {"height",600}};
    CGlobalRendering gr;
    assert(GetFullScreenFlag(false) == SDL_WINDOW_FULLSCREEN_DESKTOP);
#ifdef NATIVE_FULLSCREEN_TEST
    assert(SDL_Init(SDL_INIT_VIDEO) == 0);
    gr.sdlWindow = SDL_CreateWindow("Zero-K fullscreen probe", 100, 100, 800, 600, SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    assert(gr.sdlWindow);
    SDL_PumpEvents();
    int oldX, oldY, oldW, oldH;
    SDL_GetWindowPosition(gr.sdlWindow, &oldX, &oldY);
    SDL_GetWindowSize(gr.sdlWindow, &oldW, &oldH);
    config.values["WindowPosX"] = oldX; config.values["WindowPosY"] = oldY;
    config.values["Fullscreen"] = 1;
    gr.SetWindowAttributes(gr.sdlWindow);
    assert((SDL_GetWindowFlags(gr.sdlWindow) & SDL_WINDOW_FULLSCREEN_DESKTOP) == SDL_WINDOW_FULLSCREEN_DESKTOP);
    SDL_PumpEvents(); SDL_Delay(300);
    // Reapplying fullscreen must leave the window in the same native Space.
    gr.SetWindowAttributes(gr.sdlWindow);
    config.values["Fullscreen"] = 0;
    gr.SetWindowAttributes(gr.sdlWindow);
    SDL_PumpEvents();
    int x,y,w,h;
    SDL_GetWindowPosition(gr.sdlWindow, &x, &y); SDL_GetWindowSize(gr.sdlWindow, &w, &h);
    assert(!(SDL_GetWindowFlags(gr.sdlWindow) & SDL_WINDOW_FULLSCREEN));
    assert(x == oldX && y == oldY && w == oldW && h == oldH);
    SDL_DestroyWindow(gr.sdlWindow); SDL_Quit();
    std::puts("PASS: native Cocoa fullscreen, repeated apply, window geometry restoration");
#else
    SDL_Window window;
    gr.sdlWindow = &window;
    config.values["Fullscreen"] = 1;
    gr.SetWindowAttributes(&window);
    assert(calls == std::vector<std::string>{"enter"});
    calls.clear(); gr.SetWindowAttributes(&window);
    assert(calls.empty());
    config.values["Fullscreen"] = 0;
    gr.SetWindowAttributes(&window);
    assert((calls == std::vector<std::string>{"exit","restore","position","size","border"}));
    // Promoted borderless fullscreen on a monitor left of the primary.
    calls.clear(); config.values["WindowBorderless"] = 1;
    config.values["WindowPosX"] = -1920; config.values["WindowPosY"] = 0;
    config.values["width"] = 1920; config.values["height"] = 1080;
    gr.SetWindowAttributes(&window);
    assert(calls == std::vector<std::string>{"enter"});
    config.values["XResolutionWindowed"] = 800;
    gr.SaveWindowPosAndSize();
    assert(config.values["XResolutionWindowed"] == 800);
    // Native titlebar fullscreen also leaves the windowed profile intact.
    gr.borderless = false; gr.fullScreen = false;
    gr.SaveWindowPosAndSize();
    assert(config.values["XResolutionWindowed"] == 800);
    // A failed transition must not resize or reposition the still-fullscreen window.
    calls.clear(); failFullscreen = true; config.values["WindowBorderless"] = 0;
    gr.SetWindowAttributes(&window);
    assert(calls == std::vector<std::string>{"exit"});
    failFullscreen = false; window.flags = SDL_WINDOW_MINIMIZED;
    gr.SaveWindowPosAndSize(); assert(config.values["XResolutionWindowed"] == 800);
    window.flags = 0; gr.winSizeX = 900;
    gr.SaveWindowPosAndSize(); assert(config.values["XResolutionWindowed"] == 900);
    std::puts("PASS: fullscreen transitions, repeated apply, secondary display, failure and saved geometry");
#endif
}
'''
with tempfile.TemporaryDirectory(prefix='zk-fullscreen-') as folder:
    folder = Path(folder)
    cpp = folder / 'probe.cpp'
    cpp.write_text(harness + methods + checks)
    command = ['clang++', '-std=c++20', '-Wall', '-Wextra', '-Wno-unused-parameter', str(cpp), '-o', str(folder / 'probe')]
    if args.native:
        flags = subprocess.check_output(['sdl2-config', '--cflags', '--libs'], text=True).split()
        command += ['-DNATIVE_FULLSCREEN_TEST'] + flags
    subprocess.run(command, check=True)
    subprocess.run([str(folder / 'probe')], check=True, timeout=30)
