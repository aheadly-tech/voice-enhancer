// Exception boundary adapted from wondervip's voice-enhancer PR #4.
#import "include/AVAudioTapInstaller.h"

static NSString * const VEAVAudioTapErrorDomain = @"tech.aheadly.voice-enhancer.avaudio-tap";

static NSError *VEErrorFromException(NSException *exception) {
    return [NSError errorWithDomain:VEAVAudioTapErrorDomain
                              code:1
                          userInfo:@{
        NSLocalizedDescriptionKey: exception.reason ?: @"Audio tap operation failed.",
        @"exceptionName": exception.name
    }];
}

NSError *VEInstallInputTapSafely(AVAudioNode *node,
                                AVAudioNodeBus bus,
                                AVAudioFrameCount bufferSize,
                                AVAudioFormat *format,
                                AVAudioNodeTapBlock tapBlock) {
    @try {
        [node installTapOnBus:bus bufferSize:bufferSize format:format block:tapBlock];
        return nil;
    } @catch (NSException *exception) {
        return VEErrorFromException(exception);
    }
}

NSError *VERemoveInputTapSafely(AVAudioNode *node, AVAudioNodeBus bus) {
    @try {
        [node removeTapOnBus:bus];
        return nil;
    } @catch (NSException *exception) {
        return VEErrorFromException(exception);
    }
}
