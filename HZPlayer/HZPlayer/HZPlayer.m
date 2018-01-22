//
//  HZPlayer.m
//  HZPlayer
//
//  Created by ios开发 on 2017/8/25.
//  Copyright © 2017年 fuhanzhang. All rights reserved.
//

#import "HZPlayer.h"
#import <AVFoundation/AVFoundation.h>

#define DEVICEWITH   [UIScreen mainScreen].bounds.size.width
#define DEVICEHIGHT  [UIScreen mainScreen].bounds.size.height

@interface HZPlayer ()

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) AVPlayerItem  *playerItem;
@property (nonatomic,   copy) NSString *savePath;   //视频播放完后保存的本地路径
@property (nonatomic,   copy) NSString *videoPath;

@property (nonatomic, assign) BOOL needLoad; //需要下载
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UIView *line;  //动画线
@property (nonatomic, strong) CAAnimationGroup *animGroup ; //动画数组

@end

@implementation HZPlayer

- (void)dealloc {
    if (_player) {
        [_player pause];
        [_player.currentItem cancelPendingSeeks];
        [_player.currentItem.asset cancelLoading];
        [_player replaceCurrentItemWithPlayerItem:nil];
        _player = nil;
        _playerLayer = nil;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopAnimation];
    
    if (_needLoad) {
        [self.playerItem removeObserver:self forKeyPath:@"status"];
        [self.playerItem removeObserver:self forKeyPath:@"loadedTimeRanges"];
        [self.playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
        [self.playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    }
}

#pragma mark - initUI

- (instancetype)initWithFrame:(CGRect)frame urlPath:(NSString *)urlPath savePath:(NSString*)savePath
{
    self = [super initWithFrame:frame];
    if (self) {
        
        [self initAnimationView];

        NSFileManager *fileManager = [NSFileManager defaultManager];
        if ([fileManager fileExistsAtPath:savePath]) {
            _videoPath = savePath;
            _needLoad = NO;
            
        }else{
            _needLoad = YES;
            _videoPath = urlPath;
            [self startAnimation];
        }
        
        _savePath = savePath;
        
        if (!_videoPath) {
            return nil;
        }
        
        AVAsset *asset = nil;
        if ([_videoPath hasPrefix:@"http"]) {
            asset = [AVAsset assetWithURL:[NSURL URLWithString:_videoPath]];
            
        }else{
            asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:_videoPath]];
        }
        
        __weak typeof(self)weakSelf = self;
        [asset loadValuesAsynchronouslyForKeys:@[@"playable"] completionHandler:^{
            dispatch_async( dispatch_get_main_queue(), ^{
                [weakSelf initPlayer:asset];
            });
        }];
    }
    return self;
}

- (void)initPlayer:(AVAsset *)asset
{
    //视频方向自动调整
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    
    //手机静音模式也播放声音，如果想要与手机是否静音同步删掉即可
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
    self.playerItem = playerItem;

    self.player = [AVPlayer playerWithPlayerItem:playerItem];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.frame = self.bounds;
    [self.layer addSublayer:_playerLayer];
    [self play];
    
    [self initOthers];
    [self initNotificationAndKVO];

}

- (void)initOthers
{
    self.userInteractionEnabled = YES;
    self.backgroundColor = [UIColor blackColor];
    
    UITapGestureRecognizer*singleTapGestureRecognizer = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(btnAction_pause)];
    [self addGestureRecognizer:singleTapGestureRecognizer];
    
    self.playBtn = [[UIButton alloc]initWithFrame:CGRectMake(0, 0, 50, 50)];
    [self.playBtn setImage:[UIImage imageNamed:@"playBtn"] forState:UIControlStateNormal];
    [self.playBtn addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchUpInside];
    self.playBtn.center = self.center;
    self.playBtn.hidden = YES;
    [self addSubview:self.playBtn];
}

- (void)initAnimationView
{
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(DEVICEWITH/2-5, DEVICEHIGHT-2.0, 10, 2.0)];
    line.backgroundColor = [UIColor redColor];
    [self addSubview:line];
    line.hidden = YES;
    self.line = line;
    
    CGFloat scan = DEVICEWITH/10;
    
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.x"];
    NSValue *value = [NSNumber numberWithFloat:1.0f];
    NSValue *value1 = [NSNumber numberWithFloat:scan];
    animation.duration = 0.5;
    animation.values = @[value,value1];
    
    CABasicAnimation *banOpacity = [CABasicAnimation animationWithKeyPath:@"opacity"];
    banOpacity.fromValue = [NSNumber numberWithFloat:1.0];
    banOpacity.toValue = [NSNumber numberWithFloat:0.0];
    banOpacity.duration = 0.2;
    banOpacity.beginTime = 0.3;
    banOpacity.removedOnCompletion = NO;
    
    CAAnimationGroup *animGroup = [CAAnimationGroup animation];
    animGroup.duration = 0.5f;
    animGroup.animations = @[animation,banOpacity];
    animGroup.repeatCount=MAXFLOAT;
    self.animGroup = animGroup;
}

- (void)initNotificationAndKVO
{
    // 进入后台
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pause) name:UIApplicationDidEnterBackgroundNotification object:nil];
    // 回到前台
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    //播放完一遍
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
    
    if (_needLoad) {
        [self.playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
        [self.playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
        [self.playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
        [self.playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
    }
}

#pragma mark - action

- (void)btnAction_pause
{
    if(self.player.rate == 1.0){ //正在播
        
        self.playBtn.hidden = NO;
        [self pause];
        [self bringSubviewToFront:self.playBtn];
        
    }else{
        
        self.playBtn.hidden = YES;
        [self play];
    }
}

- (void)play
{
    if (!self.player) {
        return;
    }
    self.playBtn.hidden = YES;
    [self.player play];
}

- (void)pause
{
    if (!self.player) {
        return;
    }
    self.playBtn.hidden = NO;
    [self bringSubviewToFront:self.playBtn];
    [self.player pause];
}

- (void)startAnimation
{
    if (!self.line.hidden) {
        return;
    }
    self.line.hidden = NO;
    [self bringSubviewToFront:self.line];
    [self.line.layer addAnimation:self.animGroup forKey:@"animGroup"];
    
}

- (void)stopAnimation
{
    [self.line.layer removeAllAnimations];
    self.line.hidden= YES;
}

#pragma mark - Notification

- (void)enterForeground
{
    //动画进入后台以后会停止，回到前台先判断之前是否在动画
    if (self.line.hidden) {
        return;
    }
    self.line.hidden = YES;
    [self startAnimation];
}

//视频播放完通知
- (void)playerItemDidReachEnd:(NSNotification *)notification
{
    [self.player seekToTime:kCMTimeZero];
//    [self pause];
    
    [self play];
}

//监听获得消息
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context
{
    AVPlayerItem *playerItem = (AVPlayerItem *)object;
    
    if ([keyPath isEqualToString:@"status"]) {
        if ([playerItem status] == AVPlayerStatusReadyToPlay) {
            
            CGFloat duration = playerItem.duration.value / playerItem.duration.timescale; //视频总时间
            NSLog(@"准备好播放了，总时间：%.2f", duration);//还可以获得播放的进度，这里可以给播放进度条赋值了
            
        } else if ([playerItem status] == AVPlayerStatusFailed || [playerItem status] == AVPlayerStatusUnknown) {
            [_player pause];
        }
        
    } else if ([keyPath isEqualToString:@"loadedTimeRanges"]) {  //监听播放器的下载进度
        
        NSArray *loadedTimeRanges = [playerItem loadedTimeRanges];
        CMTimeRange timeRange = [loadedTimeRanges.firstObject CMTimeRangeValue];// 获取缓冲区域
        float startSeconds = CMTimeGetSeconds(timeRange.start);
        float durationSeconds = CMTimeGetSeconds(timeRange.duration);
        NSTimeInterval timeInterval = startSeconds + durationSeconds;// 计算缓冲总进度
        CMTime duration = playerItem.duration;
        CGFloat totalDuration = CMTimeGetSeconds(duration);
        
        NSLog(@"下载进度：%.2f   %f  %f", timeInterval / totalDuration,timeInterval,totalDuration);
        
        CGFloat timeee = [[NSString stringWithFormat:@"%.3f",timeInterval] floatValue];
        CGFloat totall = [[NSString stringWithFormat:@"%.3f",totalDuration] floatValue];
        
        if (timeee >= totall) {
            
            NSLog(@"下载wan");
            [self stopAnimation];
            
            AVMutableComposition *mixComposition = [[AVMutableComposition alloc] init];
            AVMutableCompositionTrack *audioTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                                preferredTrackID:kCMPersistentTrackID_Invalid];
            AVMutableCompositionTrack *videoTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                                preferredTrackID:kCMPersistentTrackID_Invalid];
            NSError *erroraudio = nil;
            //获取AVAsset中的音频 或 者视频
            AVAssetTrack *assetAudioTrack = [[playerItem.asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
            //向通道内加入音频或者视频
            [audioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, playerItem.asset.duration)
                                ofTrack:assetAudioTrack
                                 atTime:kCMTimeZero
                                  error:&erroraudio];
            
            NSError *errorVideo = nil;
            AVAssetTrack *assetVideoTrack = [[playerItem.asset tracksWithMediaType:AVMediaTypeVideo]firstObject];
            [videoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, playerItem.asset.duration)
                                ofTrack:assetVideoTrack
                                 atTime:kCMTimeZero
                                  error:&errorVideo];
            
            AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:mixComposition
                                                                              presetName:AVAssetExportPresetPassthrough];
            
            exporter.outputURL = [NSURL fileURLWithPath:_savePath];;
            exporter.outputFileType = AVFileTypeMPEG4;
            exporter.shouldOptimizeForNetworkUse = YES;
            [exporter exportAsynchronouslyWithCompletionHandler:^{
                
                if( exporter.status == AVAssetExportSessionStatusCompleted && _needLoad){
                    NSLog(@"保存成功");
                    _needLoad = NO;
                    [self.playerItem removeObserver:self forKeyPath:@"status"];
                    [self.playerItem removeObserver:self forKeyPath:@"loadedTimeRanges"];
                    [self.playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
                    [self.playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
                    //保存到相册（如果要保存到相册，需要先确认项目是否允许访问相册）
                    // UISaveVideoAtPathToSavedPhotosAlbum(_savePath, nil, nil, nil);
                    
                }else if( exporter.status == AVAssetExportSessionStatusFailed ){
                    
                    NSLog(@"保存shibai");
                }
            }];
        }
        
    } else if ([keyPath isEqualToString:@"playbackBufferEmpty"]) { //监听播放器在缓冲数据的状态
        
        NSLog(@"缓冲不足暂停了");
        [self startAnimation];
        
    } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
        
        NSLog(@"缓冲达到可播放程度了");
        [self stopAnimation];
        [_player play];
        
    }
}

@end
