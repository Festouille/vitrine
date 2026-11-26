#import "AutoTiming.h"
#import <AVFoundation/AVFoundation.h>
#import <NaturalLanguage/NaturalLanguage.h>
#import <Speech/Speech.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Sing/Sing.h"

enum { kWindowSeconds = 16, kMaxSampleRate = 48000 };
static atomic_flag sg_audioLock = ATOMIC_FLAG_INIT;
static atomic_bool sg_capture;
static AudioUnit sg_output;
static UInt32 sg_frames;
static double sg_rate;
static float sg_audio[kWindowSeconds * kMaxSampleRate];

static void captureAudio(AudioUnit output, double rate, UInt32 frames, const AudioBufferList *data, BOOL silent) {
    if (!atomic_load_explicit(&sg_capture, memory_order_relaxed) || rate <= 0 || rate > kMaxSampleRate
        || atomic_flag_test_and_set_explicit(&sg_audioLock, memory_order_acquire)) return;
    if (atomic_load_explicit(&sg_capture, memory_order_relaxed) && output == sg_output) {
        if (!sg_rate) sg_rate = rate;
        if (rate != sg_rate || silent) {
            atomic_store_explicit(&sg_capture, false, memory_order_relaxed);
        } else {
            UInt32 count = MIN(frames, (UInt32)(rate * kWindowSeconds) - sg_frames);
            const float *left = data->mBuffers[0].mData;
            const float *right = data->mNumberBuffers > 1 ? data->mBuffers[1].mData : NULL;
            for (UInt32 i = 0; left && i < count; i++) sg_audio[sg_frames + i] = right ? (left[i] + right[i]) * 0.5f : left[i];
            if (left) sg_frames += count;
        }
    }
    atomic_flag_clear_explicit(&sg_audioLock, memory_order_release);
}

@interface SGLyricTiming : NSObject
@property (nonatomic, strong) NSArray<SGKaraokeLine *> *plain, *timed;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *anchors;
@property (nonatomic, strong) SFSpeechRecognizer *recognizer;
@property (nonatomic) BOOL triedRecognizer;
@property (nonatomic) NSInteger duration;
@end
@implementation SGLyricTiming
@end

static NSMutableDictionary<NSString *, SGLyricTiming *> *sg_tracks;
static SGLyricTiming *sg_current, *sg_recording;
static SFSpeechRecognitionTask *sg_task;
static NSString *sg_track;
static dispatch_source_t sg_timer;
static NSUInteger sg_serial;
static NSInteger sg_start, sg_lastSubmitted;
static CFTimeInterval sg_lastView, sg_began;

static SFSpeechRecognizer *recognizerFor(NSArray<SGKaraokeLine *> *lines) {
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) [texts addObject:SGKaraokeLineText(line)];
    NLLanguage language = [NLLanguageRecognizer dominantLanguageForString:[texts componentsJoinedByString:@" "]];
    if (!language || [language isEqualToString:NLLanguageUndetermined]) return nil;
    NSLocale *preferred = NSLocale.currentLocale;
    if ([preferred.languageCode isEqualToString:language]) {
        SFSpeechRecognizer *recognizer = [[SFSpeechRecognizer alloc] initWithLocale:preferred];
        if (recognizer.supportsOnDeviceRecognition) return recognizer;
    }
    for (NSLocale *locale in [SFSpeechRecognizer.supportedLocales.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSLocale *a, NSLocale *b) {
        return [a.localeIdentifier compare:b.localeIdentifier];
    }]) {
        if (![locale.languageCode isEqualToString:language]) continue;
        SFSpeechRecognizer *recognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
        if (recognizer.supportsOnDeviceRecognition) return recognizer;
    }
    return nil;
}

static void cancelRecording(void) {
    atomic_store(&sg_capture, false);
    sg_recording = nil;
}

static void recognize(SGLyricTiming *track, AVAudioPCMBuffer *audio, NSInteger start) {
    SFSpeechAudioBufferRecognitionRequest *request = [SFSpeechAudioBufferRecognitionRequest new];
    request.requiresOnDeviceRecognition = YES;
    request.shouldReportPartialResults = NO;
    request.taskHint = SFSpeechRecognitionTaskHintDictation;
    NSUInteger serial = ++sg_serial;
    sg_task = [track.recognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        if (!result.isFinal && !error) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (serial != sg_serial) return;
            sg_task = nil;
            if (!result.isFinal || sg_current != track || ![SGKaraokePlayingTrack() isEqualToString:sg_track]) return;
            NSMutableArray<NSString *> *words = [NSMutableArray array];
            NSMutableArray<NSValue *> *times = [NSMutableArray array];
            for (SFTranscriptionSegment *segment in result.bestTranscription.segments) {
                NSInteger at = start + lround(segment.timestamp * 1000);
                NSInteger end = MIN(track.duration, at + lround(segment.duration * 1000));
                if (at < 0 || end <= at) continue;
                [words addObject:segment.substring];
                [times addObject:[NSValue valueWithRange:NSMakeRange(at, end - at)]];
            }
            NSDictionary *found = SGKaraokeRecognizedLines(track.plain, words, times);
            BOOL changed = NO;
            for (NSNumber *index in [found.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                if (track.anchors[index]) continue;
                NSRange span = [found[index] rangeValue];
                BOOL ordered = YES;
                for (NSNumber *other in track.anchors) {
                    NSRange prior = track.anchors[other].rangeValue;
                    if (other.integerValue < index.integerValue ? NSMaxRange(prior) > span.location : prior.location < NSMaxRange(span)) {
                        ordered = NO;
                        break;
                    }
                }
                if (!ordered) continue;
                track.anchors[index] = found[index];
                changed = YES;
            }
            if (changed) track.timed = SGKaraokeFollowPlainLines(track.plain, track.duration, track.anchors);
        });
    }];
    [request appendAudioPCMBuffer:audio];
    [request endAudio];
}

static void poll(void) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - sg_lastView > 1 || !SGFlag(SGKeyLyricsAutoTiming, NO) || ![SGKaraokePlayingTrack() isEqualToString:sg_track]) {
        cancelRecording();
        ++sg_serial;
        [sg_task cancel];
        sg_task = nil;
        sg_current = nil;
        sg_track = nil;
        dispatch_source_cancel(sg_timer);
        sg_timer = nil;
        SGPlayerSetSourceListener(NULL);
        return;
    }
    AudioUnit output = SGPlayerMusicOutput();
    SPTPlayerState *state = SGPlayerState();
    double sourceSeconds = SGSingSourcePosition(state);
    if (!output || !state.isPlaying || state.isPaused || state.isLoading || fabs(state.playbackSpeed - 1) > 0.01
        || !isfinite(sourceSeconds) || sourceSeconds < 0) {
        cancelRecording();
        return;
    }
    NSInteger position = lround(sourceSeconds * 1000);
    if (sg_recording && (sg_output != output || sg_recording != sg_current || !atomic_load(&sg_capture)
        || fabs((position - sg_start) - (now - sg_began) * 1000) > 400)) cancelRecording();
    if (sg_task || atomic_flag_test_and_set_explicit(&sg_audioLock, memory_order_acquire)) return;
    if (!sg_recording) {
        if (sg_current.recognizer.available && position < sg_current.duration - 2000
            && (sg_lastSubmitted < 0 || position < sg_lastSubmitted || position >= sg_lastSubmitted + 2000)) {
            sg_start = position;
            sg_began = now;
            sg_output = output;
            sg_rate = 0;
            sg_frames = 0;
            sg_recording = sg_current;
            atomic_store(&sg_capture, true);
        }
        atomic_flag_clear_explicit(&sg_audioLock, memory_order_release);
        return;
    }
    AVAudioPCMBuffer *audio = nil;
    NSInteger remaining = sg_recording.duration - sg_start;
    if (sg_rate && sg_frames >= (UInt32)(sg_rate * MIN(kWindowSeconds, MAX(2.0, remaining / 1000.0 - 0.5)))) {
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sg_rate channels:1];
        audio = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sg_frames];
        audio.frameLength = sg_frames;
        if (audio.floatChannelData) memcpy(audio.floatChannelData[0], sg_audio, sg_frames * sizeof(float));
        cancelRecording();
    } else if (now - sg_began > kWindowSeconds + 1) {
        cancelRecording();
    }
    atomic_flag_clear_explicit(&sg_audioLock, memory_order_release);
    if (audio) {
        sg_lastSubmitted = sg_start;
        recognize(sg_current, audio, sg_start);
    }
}

NSArray<SGKaraokeLine *> *SGLyricsAutoTimedLines(NSString *track, NSArray<SGKaraokeLine *> *lines) {
    if (!track.length || !lines.count || !SGFlag(SGKeyLyricsAutoTiming, NO)
        || SGKaraokeLinesTiming(lines) != SGKaraokeTimingNone) return lines;
    double seconds = SGPlayerState().duration;
    if (!isfinite(seconds) || seconds <= 0 || seconds > INT_MAX / 1000.0) return lines;
    NSInteger duration = lround(seconds * 1000);
    SGLyricTiming *entry = sg_tracks[track];
    if (entry.plain != lines || entry.duration != duration) {
        if (!sg_tracks || sg_tracks.count >= 8) sg_tracks = [NSMutableDictionary dictionary];
        entry = [SGLyricTiming new];
        entry.plain = lines;
        entry.duration = duration;
        entry.anchors = [NSMutableDictionary dictionary];
        entry.timed = SGKaraokeFollowPlainLines(lines, duration, nil);
        sg_tracks[track] = entry;
    }
    if (sg_current != entry) {
        cancelRecording();
        ++sg_serial;
        [sg_task cancel];
        sg_task = nil;
        sg_current = entry;
        sg_track = [track copy];
        sg_lastSubmitted = -1;
    }
    sg_lastView = CACurrentMediaTime();
    if (!sg_timer && [SFSpeechRecognizer authorizationStatus] == SFSpeechRecognizerAuthorizationStatusAuthorized) {
        if (!entry.triedRecognizer) {
            entry.triedRecognizer = YES;
            entry.recognizer = recognizerFor(lines);
        }
        if (entry.recognizer) {
            SGPlayerSetSourceListener(captureAudio);
            sg_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(sg_timer, DISPATCH_TIME_NOW, NSEC_PER_SEC / 5, NSEC_PER_SEC / 20);
            dispatch_source_set_event_handler(sg_timer, ^{ poll(); });
            dispatch_resume(sg_timer);
        }
    }
    return entry.timed;
}
