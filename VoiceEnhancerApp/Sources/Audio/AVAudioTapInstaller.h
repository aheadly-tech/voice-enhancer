#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL VEInstallInputTapSafely(AVAudioInputNode *inputNode,
                             AVAudioNodeBus bus,
                             AVAudioFrameCount bufferSize,
                             AVAudioFormat *format,
                             AVAudioNodeTapBlock tapBlock,
                             NSError **error);

BOOL VERemoveInputTapSafely(AVAudioInputNode *inputNode,
                            AVAudioNodeBus bus,
                            NSError **error);

NS_ASSUME_NONNULL_END
