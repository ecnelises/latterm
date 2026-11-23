//
//  TokenExecutorHelpers.m
//  iTerm2
//
//  Created by George Nachman on 2/29/24.
//

#import "TokenExecutorHelpers.h"

VT100Token *CVectorGetVT100Token(const CVector *vector, int index) {
    return (__bridge VT100Token *)vector->elements[index];
}
void CVectorSetVT100Token(const CVector *vector, int index, VT100Token *token) {
    void *previous = vector->elements[index];
    vector->elements[index] = (__bridge_retained void *)token;
    (void)CFBridgingRelease(previous);
}
void CVectorAppendVT100Token(CVector *vector, VT100Token *token) {
    CVectorAppend(vector, (__bridge_retained void *)token);
}
