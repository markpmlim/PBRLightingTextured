//
//  VirtualCamera.h
//  PhysicallyBasedLighting
//
//  Created by Mark Lim Pak Mun on 01/11/2024.
//  Copyright © 2024 Mark Lim Pak Mun. All rights reserved.
//

#import <TargetConditionals.h>
#if (TARGET_OS_IOS || TARGET_OS_TV)
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

#import <GLKit/GLKit.h>


@interface VirtualCamera : NSObject

- (nonnull instancetype)initWithScreenSize:(CGSize)size;

- (void)update:(float)duration;

- (void)resizeWithSize:(CGSize)newSize;

- (void)startDraggingFromPoint:(CGPoint)point;

- (void)dragToPoint:(CGPoint)point;

- (void)endDrag;

- (void)zoomInOrOut:(float)amount;

@property (nonatomic) GLKVector3 position;                  // returning (0.0, 0.0, 0.0)
@property (nonatomic) GLKMatrix4 viewMatrix;
@property (nonatomic) GLKQuaternion orientation;
@property (nonatomic, getter=isDragging) BOOL dragging;

@end
