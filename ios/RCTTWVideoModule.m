//
//  RCTTWVideoModule.h
//  Black
//
//  Created by Martín Fernández on 6/13/17.
//
//

#import "RCTTWVideoModule.h"

#import "RCTTWSerializable.h"

static NSString* roomDidConnect               = @"roomDidConnect";
static NSString* roomDidDisconnect            = @"roomDidDisconnect";
static NSString* roomDidFailToConnect         = @"roomDidFailToConnect";
static NSString* roomParticipantDidConnect    = @"roomParticipantDidConnect";
static NSString* roomParticipantDidDisconnect = @"roomParticipantDidDisconnect";

static NSString* participantAddedVideoTrack   = @"participantAddedVideoTrack";
static NSString* participantRemovedVideoTrack = @"participantRemovedVideoTrack";
static NSString* participantAddedAudioTrack   = @"participantAddedAudioTrack";
static NSString* participantRemovedAudioTrack = @"participantRemovedAudioTrack";
static NSString* participantEnabledVideoTrack      = @"participantEnabledVideoTrack";
static NSString* participantDisabledVideoTrack     = @"participantDisabledVideoTrack";
static NSString* participantEnabledAudioTrack      = @"participantEnabledAudioTrack";
static NSString* participantDisabledAudioTrack     = @"participantDisabledAudioTrack";

static NSString* cameraDidStart               = @"cameraDidStart";
static NSString* cameraWasInterrupted         = @"cameraWasInterrupted";
static NSString* cameraInterruptionEnded      = @"cameraInterruptionEnded";
static NSString* cameraDidStopRunning         = @"cameraDidStopRunning";
static NSString* statsReceived                = @"statsReceived";

static const CMVideoDimensions kRCTTWVideoAppCameraSourceDimensions = (CMVideoDimensions){900, 720};

static const int32_t kRCTTWVideoCameraSourceFrameRate = 15;

TVIVideoFormat *RCTTWVideoModuleCameraSourceSelectVideoFormatBySize(AVCaptureDevice *device, CMVideoDimensions targetSize) {
    TVIVideoFormat *selectedFormat = nil;
    // Ordered from smallest to largest.
    NSOrderedSet<TVIVideoFormat *> *formats = [TVICameraSource supportedFormatsForDevice:device];

    for (TVIVideoFormat *format in formats) {
        if (format.pixelFormat != TVIPixelFormatYUV420BiPlanarFullRange) {
            continue;
        }
        selectedFormat = format;
        // ^ Select whatever is available until we find one we like and short-circuit
        CMVideoDimensions dimensions = format.dimensions;

        if (dimensions.width >= targetSize.width && dimensions.height >= targetSize.height) {
            break;
        }
    }
    return selectedFormat;
}

@interface RCTTWVideoModule () <TVIRemoteParticipantDelegate, TVIRoomDelegate, TVICameraSourceDelegate>

@property (strong, nonatomic) TVICameraSource *camera;
@property (strong, nonatomic) TVILocalVideoTrack* localVideoTrack;
@property (strong, nonatomic) TVILocalAudioTrack* localAudioTrack;
@property (strong, nonatomic) TVILocalParticipant* localParticipant;
@property (strong, nonatomic) TVIRoom *room;

@end

@implementation RCTTWVideoModule

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE();

- (void)dealloc {
  // We are done with camera
  if (self.camera) {
      [self.camera stopCapture];
      self.camera = nil;
  }
}

- (dispatch_queue_t)methodQueue {
  return dispatch_get_main_queue();
}

- (NSArray<NSString *> *)supportedEvents {
  return @[
    roomDidConnect,
    roomDidDisconnect,
    roomDidFailToConnect,
    roomParticipantDidConnect,
    roomParticipantDidDisconnect,
    participantAddedVideoTrack,
    participantRemovedVideoTrack,
    participantAddedAudioTrack,
    participantRemovedAudioTrack,
    participantEnabledVideoTrack,
    participantDisabledVideoTrack,
    participantEnabledAudioTrack,
    participantDisabledAudioTrack,
    cameraDidStopRunning,
    cameraDidStart,
    cameraWasInterrupted,
    cameraInterruptionEnded,
    statsReceived
  ];
}

- (void)addLocalView:(TVIVideoView *)view {
  [self.localVideoTrack addRenderer:view];
  [self updateLocalViewMirroring:view];
}

- (void)updateLocalViewMirroring:(TVIVideoView *)view {
  if (self.camera && self.camera.device.position == AVCaptureDevicePositionFront) {
    view.mirror = true;
  }
  else {
    view.mirror = false;
  }
}
- (void)removeLocalView:(TVIVideoView *)view {
  [self.localVideoTrack removeRenderer:view];
}

- (void)removeParticipantView:(TVIVideoView *)view sid:(NSString *)sid trackSid:(NSString *)trackSid {
  // TODO: Implement this nicely
}

- (void)addParticipantView:(TVIVideoView *)view sid:(NSString *)sid trackSid:(NSString *)trackSid {
  // Lookup for the participant in the room
  TVIRemoteParticipant *participant = [self.room getRemoteParticipantWithSid:sid];
  if (participant) {
     for (TVIRemoteVideoTrackPublication *publication in participant.remoteVideoTracks) {
       if ([publication.trackSid isEqualToString:trackSid]) {
         [publication.videoTrack addRenderer:view];
       }
     }
  }
}

RCT_EXPORT_METHOD(setRemoteAudioPlayback:(NSString *)participantSid enabled:(BOOL)enabled) {
    TVIRemoteParticipant *participant = [self.room getRemoteParticipantWithSid:participantSid];
    if (participant) {
        NSArray<TVIRemoteAudioTrackPublication *> *trackPublications = participant.remoteAudioTracks;
        for(TVIRemoteAudioTrackPublication *remoteAudioTrack in trackPublications) {
            [remoteAudioTrack.remoteTrack setPlaybackEnabled:enabled];
        }
    }
}

RCT_EXPORT_METHOD(startLocalVideo) {
    TVICameraSourceOptions *options = [TVICameraSourceOptions optionsWithBlock:^(TVICameraSourceOptionsBuilder * _Nonnull builder) {

    }];
    self.camera = [[TVICameraSource alloc] initWithOptions:options delegate:self];
    if (self.camera == nil) {
        return;
    }
    self.localVideoTrack = [TVILocalVideoTrack trackWithSource:self.camera enabled:YES name:@"camera"];
    AVCaptureDevice *camera = [TVICameraSource captureDeviceForPosition:AVCaptureDevicePositionFront];
    [self.camera startCaptureWithDevice:camera completion:^(AVCaptureDevice *device,
          TVIVideoFormat *startFormat,
          NSError *error) {
        if (!error) {
            for (TVIVideoView *renderer in self.localVideoTrack.renderers) {
                [self updateLocalViewMirroring:renderer];
            }
            [self sendEventWithName:cameraDidStart body:nil];
        }
    }];
}

RCT_EXPORT_METHOD(startLocalAudio) {
    self.localAudioTrack = [TVILocalAudioTrack trackWithOptions:nil enabled:YES name:@"microphone"];
}

RCT_EXPORT_METHOD(stopLocalVideo) {
  self.localVideoTrack = nil;
  self.camera = nil;
}

RCT_EXPORT_METHOD(stopLocalAudio) {
  self.localAudioTrack = nil;
}

RCT_REMAP_METHOD(setLocalAudioEnabled, enabled:(BOOL)enabled setLocalAudioEnabledWithResolver:(RCTPromiseResolveBlock)resolve
    rejecter:(RCTPromiseRejectBlock)reject) {
  [self.localAudioTrack setEnabled:enabled];

  resolve(@(enabled));
}

RCT_REMAP_METHOD(setLocalVideoEnabled, enabled:(BOOL)enabled setLocalVideoEnabledWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
  if(self.localVideoTrack != nil){
      [self.localVideoTrack setEnabled:enabled];
      resolve(@(enabled));
  } else if(enabled) {
      [self createLocalVideoTrack];
      resolve(@true);
  } else {
      resolve(@false);
  }
}

-(void)createLocalVideoTrack {
  [self startLocalVideo];
  // Publish video so other Room Participants can subscribe
  // This check is required when TVICameraSource return nil Eg: simulator
  if(self.localVideoTrack != nil){
    [self.localParticipant publishVideoTrack:self.localVideoTrack];
  }
}

RCT_EXPORT_METHOD(flipCamera) {
    if (self.camera) {
        AVCaptureDevicePosition position = self.camera.device.position;
        AVCaptureDevicePosition nextPosition = position == AVCaptureDevicePositionFront ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
        BOOL mirror = nextPosition == AVCaptureDevicePositionFront;

        AVCaptureDevice *captureDevice = [TVICameraSource captureDeviceForPosition:nextPosition];
        [self.camera selectCaptureDevice:captureDevice completion:^(AVCaptureDevice *device,
              TVIVideoFormat *startFormat,
              NSError *error) {
            if (!error) {
                for (TVIVideoView *renderer in self.localVideoTrack.renderers) {
                    renderer.mirror = mirror;
                }
            }
        }];
    }
}

-(void)convertBaseTrackStats:(TVIBaseTrackStats *)stats result:(NSMutableDictionary *)result {
  result[@"trackSid"] = stats.trackSid;
  result[@"packetsLost"] = @(stats.packetsLost);
  result[@"codec"] = stats.codec;
  result[@"ssrc"] = stats.ssrc;
  result[@"timestamp"] = @(stats.timestamp);
}

-(void)convertRemoteTrackStats:(TVIRemoteTrackStats *)stats result:(NSMutableDictionary *)result {
  result[@"bytesReceived"] = @(stats.bytesReceived);
  result[@"packetsReceived"] = @(stats.packetsReceived);
}

-(void)convertLocalTrackStats:(TVILocalTrackStats *)stats result:(NSMutableDictionary *)result {
  result[@"bytesSent"] = @(stats.bytesSent);
  result[@"packetsSent"] = @(stats.packetsSent);
  result[@"roundTripTime"] = @(stats.roundTripTime);
}

-(NSMutableDictionary*)convertDimensions:(CMVideoDimensions)dimensions {
  NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:2];
  result[@"width"] = @(dimensions.width);
  result[@"height"] = @(dimensions.height);
  return result;
}

-(NSMutableDictionary*)convertRemoteAudioTrackStats:(TVIRemoteAudioTrackStats *)stats {
  NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:10];
  [self convertBaseTrackStats:stats result:result];
  [self convertRemoteTrackStats:stats result:result];
  result[@"audioLevel"] = @(stats.audioLevel);
  result[@"jitter"] = @(stats.jitter);
  return result;
}

-(NSMutableDictionary*)convertRemoteVideoTrackStats:(TVIRemoteVideoTrackStats *)stats {
  NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:10];
  [self convertBaseTrackStats:stats result:result];
  [self convertRemoteTrackStats:stats result:result];
  result[@"dimensions"] = [self convertDimensions:stats.dimensions];
  result[@"frameRate"] = @(stats.frameRate);
  return result;
}

-(NSMutableDictionary*)convertLocalAudioTrackStats:(TVILocalAudioTrackStats *)stats {
  NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:10];
  [self convertBaseTrackStats:stats result:result];
  [self convertLocalTrackStats:stats result:result];
  result[@"audioLevel"] = @(stats.audioLevel);
  result[@"jitter"] = @(stats.jitter);
  return result;
}

-(NSMutableDictionary*)convertLocalVideoTrackStats:(TVILocalVideoTrackStats *)stats {
  NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:10];
  [self convertBaseTrackStats:stats result:result];
  [self convertLocalTrackStats:stats result:result];
  result[@"dimensions"] = [self convertDimensions:stats.dimensions];
  result[@"frameRate"] = @(stats.frameRate);
  return result;
}

RCT_EXPORT_METHOD(getStats) {
  if (self.room) {
    [self.room getStatsWithBlock:^(NSArray<TVIStatsReport *> * _Nonnull statsReports) {
      NSMutableDictionary *eventBody = [[NSMutableDictionary alloc] initWithCapacity:10];
      for (TVIStatsReport *statsReport in statsReports) {
        NSMutableArray *audioTrackStats = [[NSMutableArray alloc] initWithCapacity:10];
        NSMutableArray *videoTrackStats = [[NSMutableArray alloc] initWithCapacity:10];
        NSMutableArray *localAudioTrackStats = [[NSMutableArray alloc] initWithCapacity:10];
        NSMutableArray *localVideoTrackStats = [[NSMutableArray alloc] initWithCapacity:10];
        for (TVIRemoteAudioTrackStats *stats in statsReport.remoteAudioTrackStats) {
          [audioTrackStats addObject:[self convertRemoteAudioTrackStats:stats]];
        }
        for (TVIRemoteVideoTrackStats *stats in statsReport.remoteVideoTrackStats) {
          [videoTrackStats addObject:[self convertRemoteVideoTrackStats:stats]];
        }
        for (TVILocalAudioTrackStats *stats in statsReport.localAudioTrackStats) {
          [localAudioTrackStats addObject:[self convertLocalAudioTrackStats:stats]];
        }
        for (TVILocalVideoTrackStats *stats in statsReport.localVideoTrackStats) {
          [localVideoTrackStats addObject:[self convertLocalVideoTrackStats:stats]];
        }
        eventBody[statsReport.peerConnectionId] = @{
          @"remoteAudioTrackStats": audioTrackStats,
          @"remoteVideoTrackStats": videoTrackStats,
          @"localAudioTrackStats": localAudioTrackStats,
          @"localVideoTrackStats": localVideoTrackStats
        };
      }
      [self sendEventWithName:statsReceived body:eventBody];
    }];
  }
}

RCT_EXPORT_METHOD(connect:(NSString *)accessToken roomName:(NSString *)roomName) {
  TVIConnectOptions *connectOptions = [TVIConnectOptions optionsWithToken:accessToken block:^(TVIConnectOptionsBuilder * _Nonnull builder) {
    if (self.localVideoTrack) {
      builder.videoTracks = @[self.localVideoTrack];
    }

    if (self.localAudioTrack) {
      builder.audioTracks = @[self.localAudioTrack];
    }

    builder.roomName = roomName;
  }];

  self.room = [TwilioVideoSDK connectWithOptions:connectOptions delegate:self];
}

RCT_EXPORT_METHOD(disconnect) {
  [self.room disconnect];
}

# pragma mark - TVICameraSourceDelegate


- (void)cameraSourceWasInterrupted:(nonnull TVICameraSource *)source reason:(AVCaptureSessionInterruptionReason)reason  API_AVAILABLE(ios(9.0)){
    NSString *reasonStr = @"unknown";
    if (@available(iOS 9.0, *)) {
        if (reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableInBackground) {
            reasonStr = @"video device not available in background";
        } else if (reason == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient) {
            reasonStr = @"audio device in use by another client";
        } else if (reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient) {
            reasonStr = @"video device in use by another client";
        } else if (reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps) {
            reasonStr = @"video device not available with multiple foreground apps";
        }
    }
    if (@available(iOS 11.1, *)) {
        if (reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableDueToSystemPressure) {
            reasonStr = @"video device not available due to system pressure";
        }
    }

    [self sendEventWithName:cameraWasInterrupted body:@{@"reason" : reasonStr }];
}

- (void)cameraSourceInterruptionEnded:(nonnull TVICameraSource *)source {
    [self sendEventWithName:cameraInterruptionEnded body:nil];
}

-(void)cameraSource:(nonnull TVICameraSource *)source didFailWithError:(nonnull NSError *)error {
  [self sendEventWithName:cameraDidStopRunning body:@{ @"error" : error.localizedDescription }];
}

# pragma mark - TVIRoomDelegate

- (void)didConnectToRoom:(TVIRoom *)room {
  NSMutableArray *participants = [NSMutableArray array];

  for (TVIRemoteParticipant *p in room.remoteParticipants) {
    p.delegate = self;
    [participants addObject:[p toJSON]];
  }
  self.localParticipant = room.localParticipant;
  [participants addObject:[self.localParticipant toJSON]];
  [self sendEventWithName:roomDidConnect body:@{ @"roomName" : room.name , @"roomSid": room.sid, @"participants" : participants }];
  
}

- (void)room:(TVIRoom *)room didDisconnectWithError:(nullable NSError *)error {
  self.room = nil;

  NSMutableDictionary *body = [@{ @"roomName": room.name, @"roomSid": room.sid } mutableCopy];

  if (error) {
    [body addEntriesFromDictionary:@{ @"error" : error.localizedDescription }];
  }

  [self sendEventWithName:roomDidDisconnect body:body];
}

- (void)room:(TVIRoom *)room didFailToConnectWithError:(nonnull NSError *)error{
  self.room = nil;

  NSMutableDictionary *body = [@{ @"roomName": room.name, @"roomSid": room.sid } mutableCopy];

  if (error) {
    [body addEntriesFromDictionary:@{ @"error" : error.localizedDescription }];
  }

  [self sendEventWithName:roomDidFailToConnect body:body];
}


- (void)room:(TVIRoom *)room participantDidConnect:(TVIRemoteParticipant *)participant {
  participant.delegate = self;

  [self sendEventWithName:roomParticipantDidConnect body:@{ @"roomName": room.name, @"roomSid": room.sid, @"participant": [participant toJSON] }];
}

- (void)room:(TVIRoom *)room participantDidDisconnect:(TVIRemoteParticipant *)participant {
  [self sendEventWithName:roomParticipantDidDisconnect body:@{ @"roomName": room.name, @"roomSid": room.sid, @"participant": [participant toJSON] }];
}

# pragma mark - TVIRemoteParticipantDelegate

- (void)didSubscribeToVideoTrack:(TVIRemoteVideoTrack *)videoTrack publication:(TVIRemoteVideoTrackPublication *)publication forParticipant:(TVIRemoteParticipant *)participant {
    [self sendEventWithName:participantAddedVideoTrack body:@{ @"participant": [participant toJSON], @"track": [publication toJSON] }];
}

- (void)didUnsubscribeFromVideoTrack:(TVIRemoteVideoTrack *)videoTrack publication:(TVIRemoteVideoTrackPublication *)publication forParticipant:(TVIRemoteParticipant *)participant {
    [self sendEventWithName:participantRemovedVideoTrack body:@{ @"participant": [participant toJSON], @"track": [publication toJSON] }];
}

- (void)didSubscribeToAudioTrack:(TVIRemoteAudioTrack *)audioTrack publication:(TVIRemoteAudioTrackPublication *)publication forParticipant:(TVIRemoteParticipant *)participant {
    [self sendEventWithName:participantAddedAudioTrack body:@{ @"participant": [participant toJSON], @"track": [publication toJSON] }];
}

- (void)didUnsubscribeFromAudioTrack:(TVIRemoteAudioTrack *)audioTrack publication:(TVIRemoteAudioTrackPublication *)publication forParticipant:(TVIRemoteParticipant *)participant {
    [self sendEventWithName:participantRemovedAudioTrack body:@{ @"participant": [participant toJSON], @"track": [publication toJSON] }];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant didEnableVideoTrack:(TVIRemoteVideoTrackPublication *)publication {
  [self sendEventWithName:participantEnabledVideoTrack body:@{ @"participant": [participant toJSON], @"track": [publication toJSON] }];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant didDisableVideoTrack:(TVIRemoteVideoTrackPublication *)publication {
  [self sendEventWithName:participantDisabledVideoTrack body:@{ @"participant": [participant toJSON], @"track": [publication toJSON] }];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant didEnableAudioTrack:(TVIRemoteAudioTrackPublication *)publication {
    [self sendEventWithName:participantEnabledAudioTrack body:@{ @"participant": [participant toJSON], @"track": [publication toJSON] }];
}

- (void)remoteParticipant:(TVIRemoteParticipant *)participant didDisableAudioTrack:(TVIRemoteAudioTrackPublication *)publication {
    [self sendEventWithName:participantDisabledAudioTrack body:@{ @"participant": [participant toJSON], @"track": [publication toJSON] }];
}

// TODO: Local participant delegates

@end
