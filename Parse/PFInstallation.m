/**
 * Copyright (c) 2015-present, Parse, LLC.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "PFInstallation.h"
#import "PFInstallationPrivate.h"

#import "BFTask+Private.h"
#import "PFApplication.h"
#import "PFAssert.h"
#import "PFCoreManager.h"
#import "PFCurrentInstallationController.h"
#import "PFFileManager.h"
#import "PFInstallationConstants.h"
#import "PFInstallationController.h"
#import "PFInstallationIdentifierStore.h"
#import "PFInternalUtils.h"
#import "PFObject+Subclass.h"
#import "PFObjectEstimatedData.h"
#import "PFObjectPrivate.h"
#import "PFOfflineStore.h"
#import "PFQueryPrivate.h"
#import "Parse_Private.h"

#if !TARGET_OS_WATCH
#import "PFPushPrivate.h"
#endif

@implementation PFInstallation (Private)

static NSSet *protectedKeys;

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        protectedKeys = PF_SET(PFInstallationKeyDeviceType,
                               PFInstallationKeyInstallationId,
                               PFInstallationKeyTimeZone,
                               PFInstallationKeyParseVersion,
                               PFInstallationKeyAppVersion,
                               PFInstallationKeyAppName,
                               PFInstallationKeyAppIdentifier);
    });
}

// Clear device token. Used for testing.
- (void)_clearDeviceToken {
    [super removeObjectForKey:PFInstallationKeyDeviceToken];
}

// Check security on delete.
- (void)checkDeleteParams {
    PFConsistencyAssert(NO, @"Installations cannot be deleted.");
}

// Validates a class name. We override this to only allow the installation class name.
+ (void)_assertValidInstanceClassName:(NSString *)className {
    PFParameterAssert([className isEqualToString:[PFInstallation parseClassName]],
                      @"Cannot initialize a PFInstallation with a custom class name.");
}

- (BOOL)_isCurrentInstallation {
    return (self == [[self class] _currentInstallationController].memoryCachedCurrentInstallation);
}

- (void)_markAllFieldsDirty {
    @synchronized(self.lock) {
        NSDictionary *estimatedData = self._estimatedData.dictionaryRepresentation;
        [estimatedData enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [super setObject:obj forKey:key];
        }];
    }
}

- (NSString *)displayClassName {
    return NSStringFromClass([PFInstallation class]);
}

///--------------------------------------
#pragma mark - Command Handlers
///--------------------------------------

- (BFTask *)handleSaveResultAsync:(NSDictionary *)result {
    @weakify(self);
    return [[super handleSaveResultAsync:result] continueWithBlock:^id(BFTask *task) {
        @strongify(self);
        BFTask *saveTask = [[[self class] _currentInstallationController] saveCurrentObjectAsync:self];
        return [saveTask continueWithResult:task];
    }];
}

///--------------------------------------
#pragma mark - Current Installation Controller
///--------------------------------------

+ (PFCurrentInstallationController *)_currentInstallationController {
    return [Parse _currentManager].coreManager.currentInstallationController;
}

@end

@implementation PFInstallation

@dynamic deviceType;
@dynamic installationId;
@dynamic deviceToken;
@dynamic timeZone;
@dynamic channels;
@dynamic badge;

///--------------------------------------
#pragma mark - PFSubclassing
///--------------------------------------

+ (NSString *)parseClassName {
    return @"_Installation";
}

+ (PFQuery *)query {
    return [super query];
}

///--------------------------------------
#pragma mark - Current Installation
///--------------------------------------

+ (instancetype)currentInstallation {
    BFTask *task = [[self _currentInstallationController] getCurrentObjectAsync];
    return [task waitForResult:nil withMainThreadWarning:NO];
}

///--------------------------------------
#pragma mark - Accessors
///--------------------------------------

- (id)objectForKey:(NSString *)key {
    if ([key isEqualToString:PFInstallationKeyBadge] && [self _isCurrentInstallation]) {
        // Update the data dictionary badge value from the device.
        [self _updateBadgeFromDevice];
    }

    return [super objectForKey:key];
}

- (void)setObject:(id)object forKey:(NSString *)key {
    PFParameterAssert(![protectedKeys containsObject:key],
                      @"Can't change the '%@' field of a PFInstallation.", key);

    if ([key isEqualToString:PFInstallationKeyBadge]) {
        // Set the application badge and update the badge value in the data dictionary.
        NSInteger badge = [object integerValue];
        PFParameterAssert(badge >= 0, @"Can't set the badge to less than zero.");

        [PFApplication currentApplication].iconBadgeNumber = badge;
        [super setObject:@(badge) forKey:PFInstallationKeyBadge];
    }

    [super setObject:object forKey:key];
}

- (void)incrementKey:(NSString *)key byAmount:(NSNumber *)amount {
    PFParameterAssert(![key isEqualToString:PFInstallationKeyBadge],
                      @"Can't atomically increment the 'badge' field of a PFInstallation.");

    [super incrementKey:key byAmount:amount];
}

- (void)removeObjectForKey:(NSString *)key {
    PFParameterAssert(![protectedKeys containsObject:key],
                      @"Can't remove the '%@' field of a PFInstallation.", key);
    PFParameterAssert(![key isEqualToString:PFInstallationKeyBadge],
                      @"Can't remove the 'badge' field of a PFInstallation.");
    [super removeObjectForKey:key];
}

// Internal mutators override the dynamic accessor and use super to avoid
// read-only checks on automatic fields.
- (void)setDeviceType:(NSString *)deviceType {
    [self _setObject:deviceType forKey:PFInstallationKeyDeviceType onlyIfDifferent:YES];
}

- (void)setInstallationId:(NSString *)installationId {
    [self _setObject:installationId forKey:PFInstallationKeyInstallationId onlyIfDifferent:YES];
}

- (void)setDeviceToken:(NSString *)deviceToken {
    [self _setObject:deviceToken forKey:PFInstallationKeyDeviceToken onlyIfDifferent:YES];
}

- (void)setDeviceTokenFromData:(NSData *)deviceTokenData {
#if !TARGET_OS_WATCH
    [self _setObject:[[PFPush pushInternalUtilClass] convertDeviceTokenToString:deviceTokenData]
              forKey:PFInstallationKeyDeviceToken
     onlyIfDifferent:YES];
#endif
}

- (void)setTimeZone:(NSString *)timeZone {
    [self _setObject:timeZone forKey:PFInstallationKeyTimeZone onlyIfDifferent:YES];
}

- (void)setChannels:(NSArray *)channels {
    [self _setObject:channels forKey:PFInstallationKeyChannels onlyIfDifferent:YES];
}

///--------------------------------------
#pragma mark - PFObject
///--------------------------------------

- (BFTask *)saveInBackground {
    [self _updateAutomaticInfo];
    return [super saveInBackground];
}

- (BFTask *)_enqueueSaveEventuallyWithChildren:(BOOL)saveChildren {
    [self _updateAutomaticInfo];
    return [super _enqueueSaveEventuallyWithChildren:saveChildren];
}

- (BFTask *)saveEventually {
    [self _updateAutomaticInfo];
    return [super saveEventually];
}

- (BFTask *)saveAsync:(BFTask *)toAwait {
    return [[super saveAsync:toAwait] continueWithBlock:^id(BFTask *task) {
        // Do not attempt to resave an object if LDS is enabled, since changing objectId is not allowed.
        if ([Parse _currentManager].offlineStoreLoaded) {
            return task;
        }

        if (task.error.code == kPFErrorObjectNotFound) {
            @synchronized (self.lock) {
                // Retry the fetch as a save operation because this Installation was deleted on the server.
                // We always want [currentInstallation save] to succeed.
                self.objectId = nil;
                [self _markAllFieldsDirty];
                return [super saveAsync:nil];
            }
        }
        return task;
    }];
}

- (BOOL)needsDefaultACL {
    return NO;
}

///--------------------------------------
#pragma mark - Automatic Info
///--------------------------------------

- (void)_updateAutomaticInfo {
    if ([self _isCurrentInstallation]) {
        @synchronized(self.lock) {
            [self _updateTimeZoneFromDevice];
            [self _updateBadgeFromDevice];
            [self _updateVersionInfoFromDevice];
        }
    }
}

- (void)_updateTimeZoneFromDevice {
    // Get the system time zone (after clearing the cached value) and update
    // the installation if necessary.
    NSString *systemTimeZoneName = [PFInternalUtils currentSystemTimeZoneName];
    if (![systemTimeZoneName isEqualToString:self.timeZone]) {
        self.timeZone = systemTimeZoneName;
    }
}

- (void)_updateBadgeFromDevice {
    // Get the application icon and update the installation if necessary.
    NSNumber *applicationBadge = @([PFApplication currentApplication].iconBadgeNumber);
    NSNumber *installationBadge = [super objectForKey:PFInstallationKeyBadge];
    if (installationBadge == nil || ![applicationBadge isEqualToNumber:installationBadge]) {
        [super setObject:applicationBadge forKey:PFInstallationKeyBadge];
    }
}

- (void)_updateVersionInfoFromDevice {
    NSDictionary *appInfo = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = appInfo[(__bridge NSString *)kCFBundleNameKey];
    NSString *appVersion = appInfo[(__bridge NSString *)kCFBundleVersionKey];
    NSString *appIdentifier = appInfo[(__bridge NSString *)kCFBundleIdentifierKey];
    // It's possible that the app was created without an info.plist and we just
    // cannot get the data we need.
    // Note: it's important to make the possibly nil string the message receptor for
    // nil propegation instead of a BAD_ACCESS
    if (appName && ![self[PFInstallationKeyAppName] isEqualToString:appName]) {
        [super setObject:appName forKey:PFInstallationKeyAppName];
    }
    if (appVersion && ![self[PFInstallationKeyAppVersion] isEqualToString:appVersion]) {
        [super setObject:appVersion forKey:PFInstallationKeyAppVersion];
    }
    if (appIdentifier && ![self[PFInstallationKeyAppIdentifier] isEqualToString:appIdentifier]) {
        [super setObject:appIdentifier forKey:PFInstallationKeyAppIdentifier];
    }
    if (![self[PFInstallationKeyParseVersion] isEqualToString:PARSE_VERSION]) {
        [super setObject:PARSE_VERSION forKey:PFInstallationKeyParseVersion];
    }
}

///--------------------------------------
#pragma mark - Data Source
///--------------------------------------

+ (id<PFObjectControlling>)objectController {
    return [Parse _currentManager].coreManager.installationController;
}

@end
