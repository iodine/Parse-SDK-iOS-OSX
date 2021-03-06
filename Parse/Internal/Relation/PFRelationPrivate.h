/**
 * Copyright (c) 2015-present, Parse, LLC.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#import <Parse/PFRelation.h>
#else
#import <ParseOSX/PFRelation.h>
#endif

@class PFDecoder;

@interface PFRelation (Private)

+ (PFRelation *)relationForObject:(PFObject *)parent forKey:(NSString *)key;
+ (PFRelation *)relationWithTargetClass:(NSString *)targetClass;
+ (PFRelation *)relationFromDictionary:(NSDictionary *)dictionary withDecoder:(PFDecoder *)decoder;
- (void)ensureParentIs:(PFObject *)someParent andKeyIs:(NSString *)someKey;
- (NSDictionary *)encodeIntoDictionary;
- (BOOL)_hasKnownObject:(PFObject *)object;
- (void)_addKnownObject:(PFObject *)object;
- (void)_removeKnownObject:(PFObject *)object;

@end
