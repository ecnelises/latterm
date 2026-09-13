//
//  iTermScrollWheelStateMachineTypes.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermScrollWheelStateMachineState) {
    iTermScrollWheelStateMachineStateGround,
    iTermScrollWheelStateMachineStateStartDrag,
    iTermScrollWheelStateMachineStateDrag,
    iTermScrollWheelStateMachineStateTouchAndHold,
};

NS_ASSUME_NONNULL_END
