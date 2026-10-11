#ifndef VOICE_ENHANCER_AV_AUDIO_TAP_INSTALLER_H
#define VOICE_ENHANCER_AV_AUDIO_TAP_INSTALLER_H

#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

// Lifecycle operations only: never call these from an audio callback.
// Return nil on success, or the caught Objective-C exception as an NSError.
// The caller must discard the capture graph after a failed operation because
// AVAudioEngine does not promise that its state is usable after an exception.
NSError * _Nullable VEInstallInputTapSafely(AVAudioNode *node,
                                           AVAudioNodeBus bus,
                                           AVAudioFrameCount bufferSize,
                                           AVAudioFormat *format,
                                           AVAudioNodeTapBlock tapBlock);

NSError * _Nullable VERemoveInputTapSafely(AVAudioNode *node,
                                          AVAudioNodeBus bus);

NS_ASSUME_NONNULL_END

#endif // VOICE_ENHANCER_AV_AUDIO_TAP_INSTALLER_H
