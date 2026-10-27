#import <AppKit/AppKit.h>
#include <cassert>
#include <cstdio>
#include "System/Platform/WindowManagerHelper.h"

int main()
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		NSMenu* main = [[NSMenu alloc] init];
		NSMenuItem* app = [[NSMenuItem alloc] init];
		NSMenu* menu = [[NSMenu alloc] init];
		[menu addItemWithTitle:@"About Zero-K" action:nil keyEquivalent:@""];
		app.submenu = menu;
		[main addItem:app];
		NSApp.mainMenu = main;
		unsetenv("ZEROK_UPDATE_REQUEST_ID");
		WindowManagerHelper::AddUpdateMenuItem();
		assert(menu.numberOfItems == 1);
		setenv("ZEROK_UPDATE_REQUEST_ID", "update-menu-test", 1);
		WindowManagerHelper::AddUpdateMenuItem();
		WindowManagerHelper::AddUpdateMenuItem();
		assert(menu.numberOfItems == 2);
		NSMenuItem* check = [menu itemAtIndex:1];
		assert([check.title isEqualToString:@"Check for Updates…"]);
		__block bool received = false;
		id observer = [[NSDistributedNotificationCenter defaultCenter]
			addObserverForName:@"org.zerok.macos.checkForUpdates" object:@"update-menu-test"
			queue:nil usingBlock:^(NSNotification*) { received = true; }];
		[NSApp sendAction:check.action to:check.target from:check];
		NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:3];
		while (!received && deadline.timeIntervalSinceNow > 0)
			[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
		assert(received);
		[[NSDistributedNotificationCenter defaultCenter] removeObserver:observer];
		std::puts("Update menu visibility, duplicate prevention and launcher notification checks passed");
	}
}
