//
//  HZPlayer.h
//  HZPlayer
//
//  Created by ios开发 on 2017/8/25.
//  Copyright © 2017年 fuhanzhang. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface HZPlayer : UIView

/**
 初始化方法

 @param frame frame
 @param urlPath 下载路径
 @param savePath 本地路径或者将要保存的路径

 */
- (instancetype)initWithFrame:(CGRect)frame urlPath:(NSString *)urlPath savePath:(NSString*)savePath;

//播放
- (void)play;

//暂停
- (void)pause;

@end
