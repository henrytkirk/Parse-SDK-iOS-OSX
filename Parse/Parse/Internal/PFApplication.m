/**
 * Copyright (c) 2015-present, Parse, LLC.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "PFApplication.h"

#if TARGET_OS_IOS || TARGET_OS_TV
#import <UIKit/UIKit.h>
#elif PF_TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif
@interface PFApplication() {
    NSUInteger _iconBadgeNumber;
    BOOL _isTrackingIconBadgeNumber;
    UIApplication *_iconBadgeNumberObservedApplication;
}
@end

@implementation PFApplication

///--------------------------------------
#pragma mark - Init
///--------------------------------------

+ (instancetype)currentApplication {
    static PFApplication *application;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        application = [[self alloc] init];
    });
    return application;
}

///--------------------------------------
#pragma mark - Accessors
///--------------------------------------

- (BOOL)isAppStoreEnvironment {
#if TARGET_OS_IOS && !TARGET_IPHONE_SIMULATOR
    return ([[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"] == nil);
#endif

    return NO;
}

- (BOOL)isExtensionEnvironment {
    return [[NSBundle mainBundle].bundlePath hasSuffix:@".appex"];
}

- (NSInteger)iconBadgeNumber {
#if TARGET_OS_WATCH
    return 0;
#elif TARGET_OS_IOS || TARGET_OS_TV
    [self _startTrackingIconBadgeNumberIfNeeded];
    return _iconBadgeNumber;
#elif PF_TARGET_OS_OSX
    // Make sure not to use `NSApp` here, because it doesn't work sometimes,
    // `NSApplication +sharedApplication` does though.
    NSString *badgeLabel = [[NSApplication sharedApplication] dockTile].badgeLabel;
    if (badgeLabel.length == 0) {
        return 0;
    }

    NSScanner *scanner = [NSScanner localizedScannerWithString:badgeLabel];

    NSInteger number = 0;
    [scanner scanInteger:&number];
    if (scanner.scanLocation != badgeLabel.length) {
        return 0;
    }

    return number;
#endif
}

- (void)setIconBadgeNumber:(NSInteger)iconBadgeNumber {
    if (self.iconBadgeNumber != iconBadgeNumber) {
#if TARGET_OS_IOS || TARGET_OS_TV
        _iconBadgeNumber = iconBadgeNumber;
        dispatch_block_t block = ^{
            if (@available(iOS 1.0, tvOS 10.0, *)) {
                self.systemApplication.applicationIconBadgeNumber = iconBadgeNumber;
            }
        };
        if ([NSThread currentThread].isMainThread) {
            block();
        } else {
            dispatch_async(dispatch_get_main_queue(), block);
        }
#elif PF_TARGET_OS_OSX
        [[NSApplication sharedApplication] dockTile].badgeLabel = [@(iconBadgeNumber) stringValue];
#endif
    }
}

#if TARGET_OS_IOS || TARGET_OS_TV
/// Starts keeping `_iconBadgeNumber` in sync with the app icon badge number, the first time it's needed.
/// This doesn't happen at init, because the first badge number read can block the main queue for minutes
/// on a freshly booted iOS 27 simulator, and apps that don't use the badge never need it.
/// The first read runs on the main queue. Called off the main queue, the cached value is returned until then.
- (void)_startTrackingIconBadgeNumberIfNeeded {
    if (@available(iOS 1.0, tvOS 10.0, *)) {
        @synchronized (self) {
            if (_isTrackingIconBadgeNumber) {
                return;
            }
            _isTrackingIconBadgeNumber = YES;
        }
        dispatch_block_t block = ^{
            UIApplication *systemApplication = self.systemApplication;
            [systemApplication addObserver:self forKeyPath:@"applicationIconBadgeNumber" options:NSKeyValueObservingOptionNew context:nil];
            self->_iconBadgeNumberObservedApplication = systemApplication;
            self->_iconBadgeNumber = systemApplication.applicationIconBadgeNumber;
        };
        if ([NSThread currentThread].isMainThread) {
            block();
        } else {
            dispatch_async(dispatch_get_main_queue(), block);
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"applicationIconBadgeNumber"] && change) {
        _iconBadgeNumber = [change[@"new"] integerValue];
    }
}
#endif

- (UIApplication *)systemApplication {
#if TARGET_OS_WATCH
    return nil;
#else
    // Workaround to make `sharedApplication` still be called even if compiling for App Extensions or WatchKit apps.
    return [UIApplication performSelector:@selector(sharedApplication)];
#endif
}

- (void)dealloc {
#if TARGET_OS_IOS || TARGET_OS_TV
    if (@available(iOS 1.0, tvOS 10.0, *)) {
        [_iconBadgeNumberObservedApplication removeObserver:self forKeyPath:@"applicationIconBadgeNumber"];
    }
#endif
}

@end
