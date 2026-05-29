#import "AVAudioTapInstaller.h"

static NSString * const VEAVAudioTapErrorDomain = @"tech.aheadly.voice-enhancer.avaudio-tap";

static NSError *VEErrorFromException(NSException *exception) {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (exception.reason != nil) {
        userInfo[NSLocalizedDescriptionKey] = exception.reason;
    }
    userInfo[@"exceptionName"] = exception.name;
    return [NSError errorWithDomain:VEAVAudioTapErrorDomain code:1 userInfo:userInfo];
}

BOOL VEInstallInputTapSafely(AVAudioInputNode *inputNode,
                             AVAudioNodeBus bus,
                             AVAudioFrameCount bufferSize,
                             AVAudioFormat *format,
                             AVAudioNodeTapBlock tapBlock,
                             NSError **error) {
    @try {
        [inputNode installTapOnBus:bus bufferSize:bufferSize format:format block:tapBlock];
        return YES;
    } @catch (NSException *exception) {
        if (error != nil) {
            *error = VEErrorFromException(exception);
        }
        return NO;
    }
}

BOOL VERemoveInputTapSafely(AVAudioInputNode *inputNode,
                            AVAudioNodeBus bus,
                            NSError **error) {
    @try {
        [inputNode removeTapOnBus:bus];
        return YES;
    } @catch (NSException *exception) {
        if (error != nil) {
            *error = VEErrorFromException(exception);
        }
        return NO;
    }
}
