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
		assert(menu.numberOfItems == 3);
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
		NSMenuItem* automatic = [menu itemAtIndex:2];
		assert([automatic.title isEqualToString:@"Check Automatically"]);
		assert(automatic.state == NSControlStateValueOff);
		received = false;
		observer = [[NSDistributedNotificationCenter defaultCenter]
			addObserverForName:@"org.zerok.macos.toggleAutomaticChecks" object:@"update-menu-test"
			queue:nil usingBlock:^(NSNotification*) { received = true; }];
		[NSApp sendAction:automatic.action to:automatic.target from:automatic];
		deadline = [NSDate dateWithTimeIntervalSinceNow:3];
		while (!received && deadline.timeIntervalSinceNow > 0)
			[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
		assert(received);
		[[NSDistributedNotificationCenter defaultCenter] removeObserver:observer];
		for (NSNumber* enabled in @[@YES, @NO]) {
			[[NSDistributedNotificationCenter defaultCenter]
				postNotificationName:@"org.zerok.macos.automaticChecksChanged" object:@"update-menu-test"
				userInfo:@{@"enabled": enabled} deliverImmediately:YES];
			deadline = [NSDate dateWithTimeIntervalSinceNow:3];
			while (automatic.state != enabled.integerValue && deadline.timeIntervalSinceNow > 0)
				[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
			assert(automatic.state == enabled.integerValue);
		}
		std::puts("Update menu visibility, duplicate prevention and launcher notification checks passed");
	}
}
