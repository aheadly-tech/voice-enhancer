#import <AVFoundation/AVFoundation.h>
#import "AVAudioTapInstaller.h"

// Throw in Objective-C so no Swift frame is unwound by NSException.
// No hardware engine or microphone permission is needed by this double.
@interface VETestTapNode : AVAudioMixerNode
@property(nonatomic) BOOL failInstall;
@property(nonatomic) BOOL failRemove;
@property(nonatomic) BOOL partiallyInstall;
@property(nonatomic) BOOL omitReason;
@property(nonatomic) BOOL installed;
@property(nonatomic) AVAudioNodeBus lastBus;
@property(nonatomic) AVAudioFrameCount lastBufferSize;
@property(nonatomic, strong) AVAudioFormat *lastFormat;
@property(nonatomic, copy) AVAudioNodeTapBlock lastBlock;
@end

@implementation VETestTapNode
- (void)installTapOnBus:(AVAudioNodeBus)bus
            bufferSize:(AVAudioFrameCount)bufferSize
                format:(AVAudioFormat *)format
                 block:(AVAudioNodeTapBlock)block {
    self.lastBus = bus;
    self.lastBufferSize = bufferSize;
    self.lastFormat = format;
    self.lastBlock = block;
    if (self.failInstall) {
        self.installed = self.partiallyInstall;
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                      reason:self.omitReason ? nil : @"format mismatch"
                                    userInfo:nil];
    }
    if (self.installed) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                      reason:@"duplicate tap"
                                    userInfo:nil];
    }
    self.installed = YES;
}
- (void)removeTapOnBus:(AVAudioNodeBus)bus {
    self.lastBus = bus;
    if (self.failRemove) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                      reason:@"removal failed"
                                    userInfo:nil];
    }
    self.installed = NO;
    self.lastBlock = nil;
}
@end

static int failures = 0;
static int checks = 0;
static void expect(BOOL condition, const char *description) {
    ++checks;
    if (!condition) {
        ++failures;
        fprintf(stderr, "FAIL: %s\n", description);
    }
}

int main(void) {
    @autoreleasepool {
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:1];
        __block BOOL callbackRan = NO;
        AVAudioNodeTapBlock block = ^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            callbackRan = YES;
        };
        VETestTapNode *node = [VETestTapNode new];
        expect(VEInstallInputTapSafely(node, 3, 512, format, block) == nil, "successful install returns nil");
        expect(node.installed && node.lastBus == 3 && node.lastBufferSize == 512,
               "install forwards bus and buffer size");
        expect(node.lastFormat == format, "install forwards format unchanged");
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:1];
        node.lastBlock(buffer, [AVAudioTime timeWithSampleTime:0 atRate:48000]);
        expect(callbackRan, "install forwards callback");
        expect(VERemoveInputTapSafely(node, 3) == nil && !node.installed,
               "successful removal clears tap");

        node.failInstall = YES;
        NSError *error = VEInstallInputTapSafely(node, 0, 512, format, block);
        expect(error != nil && [error.domain isEqualToString:@"tech.aheadly.voice-enhancer.avaudio-tap"],
               "installation exception becomes NSError");
        expect([error.localizedDescription isEqualToString:@"format mismatch"], "exception reason retained");
        expect([error.userInfo[@"exceptionName"] isEqualToString:NSInternalInconsistencyException],
               "exception name retained");
        node.omitReason = YES;
        error = VEInstallInputTapSafely(node, 0, 512, format, block);
        expect([error.localizedDescription isEqualToString:@"Audio tap operation failed."],
               "missing exception reason has fallback");

        node.partiallyInstall = YES;
        expect(VEInstallInputTapSafely(node, 0, 512, format, block) != nil && node.installed,
               "partial install still reports failure");
        expect(VERemoveInputTapSafely(node, 0) == nil && !node.installed,
               "failed partial installation can be cleaned up");
        node.failInstall = NO;
        expect(VEInstallInputTapSafely(node, 0, 512, format, block) == nil,
               "install succeeds after failed attempt and cleanup");
        expect(VEInstallInputTapSafely(node, 0, 512, format, block) != nil,
               "duplicate installation becomes an error instead of aborting");
        node.failRemove = YES;
        error = VERemoveInputTapSafely(node, 0);
        expect(error != nil && [error.localizedDescription isEqualToString:@"removal failed"],
               "removal exception becomes NSError");
        node.failRemove = NO;
        expect(VERemoveInputTapSafely(node, 0) == nil, "later removal succeeds");
        VETestTapNode *replacement = [VETestTapNode new];
        expect(VEInstallInputTapSafely(replacement, 0, 512, format, block) == nil,
               "fresh node can install after prior graph failure");
        expect(VERemoveInputTapSafely(replacement, 0) == nil, "replacement tap cleans up");
        printf("Tap support: %d checks, %d failures\n", checks, failures);
    }
    return failures ? 1 : 0;
}
