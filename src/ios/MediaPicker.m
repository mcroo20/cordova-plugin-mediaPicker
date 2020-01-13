/********* MediaPicker.m Cordova Plugin Implementation *******/

#import <Cordova/CDV.h>
#import "DmcPickerViewController.h"
@interface MediaPicker : CDVPlugin <DmcPickerDelegate>{
  // Member variables go here.
    NSString* callbackId;
}

- (void)getMedias:(CDVInvokedUrlCommand*)command;
- (void)takePhoto:(CDVInvokedUrlCommand*)command;
- (void)extractThumbnail:(CDVInvokedUrlCommand*)command;

@end

@implementation MediaPicker

- (void)getMedias:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSDictionary *options = [command.arguments objectAtIndex: 0];
    DmcPickerViewController * dmc=[[DmcPickerViewController alloc] init];
    @try{
        dmc.selectMode=[[options objectForKey:@"selectMode"]integerValue];
    }@catch (NSException *exception) {
        NSLog(@"Exception: %@", exception);
    }
    @try{
        dmc.maxSelectCount=[[options objectForKey:@"maxSelectCount"]integerValue];
    }@catch (NSException *exception) {
        NSLog(@"Exception: %@", exception);
    }
    @try{
        dmc.maxSelectSize=[[options objectForKey:@"maxSelectSize"]integerValue];
    }@catch (NSException *exception) {
        NSLog(@"Exception: %@", exception);
    }
    dmc.modalPresentationStyle = 0;
    if (@available(iOS 13.0, *)) {
        dmc.modalInPresentation = true;
    }
    dmc._delegate=self;
    [self.viewController presentViewController:[[UINavigationController alloc]initWithRootViewController:dmc] animated:YES completion:nil];
}

-(void) resultPicker:(NSMutableArray*) selectArray
{
    
    NSString * tmpDir = NSTemporaryDirectory();
    NSString *dmcPickerPath = [tmpDir stringByAppendingPathComponent:@"dmcPicker"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath:dmcPickerPath ]){
       [fileManager createDirectoryAtPath:dmcPickerPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSMutableArray * aListArray=[[NSMutableArray alloc] init];
    if([selectArray count]<=0){
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
        return;
    }

    dispatch_async(dispatch_get_global_queue (DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int index=0;
        for(PHAsset *asset in selectArray){
            @autoreleasepool {
                if(asset.mediaType==PHAssetMediaTypeImage){
                    [self imageToSandbox:asset dmcPickerPath:dmcPickerPath aListArray:aListArray selectArray:selectArray index:index];
                }else{
//                    [self videoToSandboxCompress:asset dmcPickerPath:dmcPickerPath aListArray:aListArray selectArray:selectArray index:index];
                    [self videoToSandbox:asset dmcPickerPath:dmcPickerPath aListArray:aListArray selectArray:selectArray index:index];
                }
            }
            index++;
        }
    });

}

-(void)imageToSandbox:(PHAsset *)asset dmcPickerPath:(NSString*)dmcPickerPath aListArray:(NSMutableArray*)aListArray selectArray:(NSMutableArray*)selectArray index:(int)index{
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    options.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        NSString *compressCompletedjs = [NSString stringWithFormat:@"MediaPicker.icloudDownloadEvent(%f,%i)", progress,index];
        [self.commandDelegate evalJs:compressCompletedjs];
    };
    [[PHImageManager defaultManager] requestImageDataForAsset:asset  options:options resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
        if(imageData != nil) {
            NSString *filename=[asset valueForKey:@"filename"];
            NSString *fullpath=[NSString stringWithFormat:@"%@/%@%@", dmcPickerPath,[[NSProcessInfo processInfo] globallyUniqueString], filename];
            NSNumber *size=[NSNumber numberWithLong:imageData.length];

            NSError *error = nil;
            if (![imageData writeToFile:fullpath options:NSAtomicWrite error:&error]) {
                NSLog(@"%@", [error localizedDescription]);
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:callbackId];
            } else {
                
                NSDictionary *dict=[NSDictionary dictionaryWithObjectsAndKeys:fullpath,@"path",[[NSURL fileURLWithPath:fullpath] absoluteString],@"uri",@"image",@"mediaType",size,@"size",[NSNumber numberWithInt:index],@"index", nil];
                [aListArray addObject:dict];
                if([aListArray count]==[selectArray count]){
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
                }
            }
        } else {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:NSLocalizedString(@"photo_download_failed", nil)] callbackId:callbackId];
        }
    }];
}

- (void)getExifForKey:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSString *path= [command.arguments objectAtIndex: 0];
    NSString *key  = [command.arguments objectAtIndex: 1];

    NSData *imageData = [NSData dataWithContentsOfFile:path];
    //UIImage * image= [[UIImage alloc] initWithContentsOfFile:[options objectForKey:@"path"] ];
    CGImageSourceRef imageRef=CGImageSourceCreateWithData((CFDataRef)imageData, NULL);
    
    CFDictionaryRef imageInfo = CGImageSourceCopyPropertiesAtIndex(imageRef, 0,NULL);
    
    NSDictionary  *nsdic = (__bridge_transfer  NSDictionary*)imageInfo;
    NSString* orientation=[nsdic objectForKey:key];
   
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:orientation] callbackId:callbackId];


}


-(void)videoToSandbox:(PHAsset *)asset dmcPickerPath:(NSString*)dmcPickerPath aListArray:(NSMutableArray*)aListArray selectArray:(NSMutableArray*)selectArray index:(int)index{
    PHVideoRequestOptions *options = [[PHVideoRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        NSString *compressCompletedjs = [NSString stringWithFormat:@"MediaPicker.icloudDownloadEvent(%f,%i)", progress,index];
        [self.commandDelegate evalJs:compressCompletedjs];
    };
    [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:options resultHandler:^(AVAsset *avsset, AVAudioMix *audioMix, NSDictionary *info) {
        if ([avsset isKindOfClass:[AVURLAsset class]]) {
            NSString *filename = [asset valueForKey:@"filename"];
            AVURLAsset* urlAsset = (AVURLAsset*)avsset;
            
            NSString *fullpath=[NSString stringWithFormat:@"%@/%@", dmcPickerPath,filename];
            NSLog(@"%@", urlAsset.URL);
            NSData *data = [NSData dataWithContentsOfURL:urlAsset.URL options:NSDataReadingUncached error:nil];

            NSNumber* size=[NSNumber numberWithLong: data.length];
            NSError *error = nil;
            if (![data writeToFile:fullpath options:NSAtomicWrite error:&error]) {
                NSLog(@"%@", [error localizedDescription]);
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:callbackId];
            } else {
                
                NSDictionary *dict=[NSDictionary dictionaryWithObjectsAndKeys:fullpath,@"path",[[NSURL fileURLWithPath:fullpath] absoluteString],@"uri",size,@"size",@"video",@"mediaType" ,[NSNumber numberWithInt:index],@"index", nil];
                [aListArray addObject:dict];
                if([aListArray count]==[selectArray count]){
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
                }
            }
           
        }
    }];

}

-(void)videoToSandboxCompress:(PHAsset *)asset dmcPickerPath:(NSString*)dmcPickerPath aListArray:(NSMutableArray*)aListArray selectArray:(NSMutableArray*)selectArray index:(int)index{
    NSString *compressStartjs = [NSString stringWithFormat:@"MediaPicker.compressEvent('%@',%i)", @"start",index];
    [self.commandDelegate evalJs:compressStartjs];
    [[PHImageManager defaultManager] requestExportSessionForVideo:asset options:nil exportPreset:AVAssetExportPresetMediumQuality resultHandler:^(AVAssetExportSession *exportSession, NSDictionary *info) {
        

        NSString *fullpath=[NSString stringWithFormat:@"%@/%@.%@", dmcPickerPath,[[NSProcessInfo processInfo] globallyUniqueString], @"mp4"];
        NSURL *outputURL = [NSURL fileURLWithPath:fullpath];
        
        NSLog(@"this is the final path %@",outputURL);
        
        exportSession.outputFileType=AVFileTypeMPEG4;
        
        exportSession.outputURL=outputURL;

        [exportSession exportAsynchronouslyWithCompletionHandler:^{

            if (exportSession.status == AVAssetExportSessionStatusFailed) {
                NSString * errorString = [NSString stringWithFormat:@"videoToSandboxCompress failed %@",exportSession.error];
               [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorString] callbackId:callbackId];
                NSLog(@"failed");
                
            } else if(exportSession.status == AVAssetExportSessionStatusCompleted){
                
                NSLog(@"completed!");
                NSString *compressCompletedjs = [NSString stringWithFormat:@"MediaPicker.compressEvent('%@',%i)", @"completed",index];
                [self.commandDelegate evalJs:compressCompletedjs];
                NSDictionary *dict=[NSDictionary dictionaryWithObjectsAndKeys:fullpath,@"path",[[NSURL fileURLWithPath:fullpath] absoluteString],@"uri",@"video",@"mediaType" ,[NSNumber numberWithInt:index],@"index", nil];
                [aListArray addObject:dict];
                if([aListArray count]==[selectArray count]){
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
                }
            }
            
        }];
        
    }];
}



-(NSString*)thumbnailVideo:(NSString*)path quality:(NSInteger)quality {
    UIImage *shotImage;
    //视频路径URL
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:fileURL options:nil];
    
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    
    gen.appliesPreferredTrackTransform = YES;
    
    CMTime time = CMTimeMakeWithSeconds(0.0, 600);
    
    NSError *error = nil;
    
    CMTime actualTime;
    
    CGImageRef image = [gen copyCGImageAtTime:time actualTime:&actualTime error:&error];
    
    shotImage = [[UIImage alloc] initWithCGImage:image];
    
    CGImageRelease(image);
    CGFloat q=quality/100.0f;
    NSString *thumbnail=[UIImageJPEGRepresentation(shotImage,q) base64EncodedStringWithOptions:0];
    return thumbnail;
}

- (void)takePhoto:(CDVInvokedUrlCommand*)command
{


}

-(UIImage*)getThumbnailImage:(NSString*)path type:(NSString*)mtype{
    UIImage *result;
    if([@"image" isEqualToString: mtype]){
        result= [[UIImage alloc] initWithContentsOfFile:path];
    }else{
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        
        AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:fileURL options:nil];
        
        AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        
        gen.appliesPreferredTrackTransform = YES;
        
        CMTime time = CMTimeMakeWithSeconds(0.0, 600);
        
        NSError *error = nil;
        
        CMTime actualTime;
        
        CGImageRef image = [gen copyCGImageAtTime:time actualTime:&actualTime error:&error];
        
        result = [[UIImage alloc] initWithCGImage:image];
    }
    return result;
}

-(NSString*)thumbnailImage:(UIImage*)result quality:(NSInteger)quality{
    NSInteger qu = quality>0?quality:3;
    CGFloat q=qu/100.0f;
    NSString *thumbnail=[UIImageJPEGRepresentation(result,q) base64EncodedStringWithOptions:0];
    return thumbnail;
}

- (void)extractThumbnail:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSMutableDictionary *options = [command.arguments objectAtIndex: 0];
    UIImage * image=[self getThumbnailImage:[options objectForKey:@"path"] type:[options objectForKey:@"mediaType"]];
    NSString *thumbnail=[self thumbnailImage:image quality:[[options objectForKey:@"thumbnailQuality"] integerValue]];

    [options setObject:thumbnail forKey:@"thumbnailBase64"];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options] callbackId:callbackId];
}

- (void)compressImage:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSMutableDictionary *options = [command.arguments objectAtIndex: 0];

    NSInteger quality=[[options objectForKey:@"quality"] integerValue];
    if(quality<100&&[@"image" isEqualToString: [options objectForKey:@"mediaType"]]){
        UIImage *result = [[UIImage alloc] initWithContentsOfFile: [options objectForKey:@"path"]];
        NSInteger qu = quality>0?quality:3;
        CGFloat q=qu/100.0f;
        NSData *data =UIImageJPEGRepresentation(result,q);
        NSString *dmcPickerPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"dmcPicker"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if(![fileManager fileExistsAtPath:dmcPickerPath ]){
           [fileManager createDirectoryAtPath:dmcPickerPath withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString *filename=[NSString stringWithFormat:@"%@%@%@",@"dmcMediaPickerCompress", [self currentTimeStr],@".jpg"];
        NSString *fullpath=[NSString stringWithFormat:@"%@/%@", dmcPickerPath,filename];
        NSNumber* size=[NSNumber numberWithLong: data.length];
        NSError *error = nil;
        if (![data writeToFile:fullpath options:NSAtomicWrite error:&error]) {
            NSLog(@"%@", [error localizedDescription]);
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:callbackId];
        } else {
            [options setObject:fullpath forKey:@"path"];
            [options setObject:[[NSURL fileURLWithPath:fullpath] absoluteString] forKey:@"uri"];
            [options setObject:size forKey:@"size"];
            [options setObject:filename forKey:@"name"];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options] callbackId:callbackId];
        }        
        
    }else{
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options] callbackId:callbackId];
    }
}

//获取当前时间戳
- (NSString *)currentTimeStr{
    NSDate* date = [NSDate dateWithTimeIntervalSinceNow:0];//获取当前时间0秒后的时间
    NSTimeInterval time=[date timeIntervalSince1970]*1000;// *1000 是精确到毫秒，不乘就是精确到秒
    NSString *timeString = [NSString stringWithFormat:@"%.0f", time];
    return timeString;
}


-(void)fileToBlob:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSData *result =[NSData dataWithContentsOfFile:[command.arguments objectAtIndex: 0]];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArrayBuffer:result]callbackId:command.callbackId];
}

- (void)getFileInfo:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSString *type= [command.arguments objectAtIndex: 1];
    NSURL *url;
    NSString *path;
    if([type isEqualToString:@"uri"]){
        NSString *str=[command.arguments objectAtIndex: 0];
        url = [NSURL URLWithString:str];
        path= url.path;
    }else{
        path= [command.arguments objectAtIndex: 0];
        url =  [NSURL fileURLWithPath:path];
    }
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithCapacity:5];
    [options setObject:path forKey:@"path"];
    [options setObject:url.absoluteString forKey:@"uri"];

    NSNumber * size = [NSNumber numberWithUnsignedLongLong:[[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize]];
    [options setObject:size forKey:@"size"];
    NSString *fileName = [[NSFileManager defaultManager] displayNameAtPath:path];
    [options setObject:fileName forKey:@"name"];
    if([[self getMIMETypeURLRequestAtPath:path] containsString:@"video"]){
        [options setObject:@"video" forKey:@"mediaType"];
    }else{
        [options setObject:@"image" forKey:@"mediaType"];
    }
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options] callbackId:callbackId];
}


-(NSString *)getMIMETypeURLRequestAtPath:(NSString*)path
{
    //1.确定请求路径
    NSURL *url = [NSURL fileURLWithPath:path];
    
    //2.创建可变的请求对象
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    //3.发送请求
    NSHTTPURLResponse *response = nil;
    [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];
    
    NSString *mimeType = response.MIMEType;
    return mimeType;
}


-(void) writeImagesToMovieAtPath:(NSString *) path withSize:(CGSize) size
{
//  NSString *documentsDirectoryPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
//  NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documentsDirectoryPath error:nil];
//  for (NSString *tString in dirContents)
//  {
//    if ([tString isEqualToString:@"essai.mp4"])
//    {
//        [[NSFileManager defaultManager]removeItemAtPath:[NSString stringWithFormat:@"%@/%@",documentsDirectoryPath,tString] error:nil];
//
//    }
//  }
//
//  NSLog(@"Write Started");
//
//  NSError *error = nil;
//
//  AVAssetWriter *videoWriter = [[AVAssetWriter alloc] initWithURL:
//                              [NSURL fileURLWithPath:path] fileType:AVFileTypeMPEG4
//                                                          error:&error];
//  NSParameterAssert(videoWriter);
//
//  NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
//                               AVVideoCodecH264, AVVideoCodecKey,
//                               [NSNumber numberWithInt:size.width], AVVideoWidthKey,
//                               [NSNumber numberWithInt:size.height], AVVideoHeightKey,
//                               nil];
//
//
//  AVAssetWriterInput* videoWriterInput = [AVAssetWriterInput
//                                         assetWriterInputWithMediaType:AVMediaTypeVideo
//                                         outputSettings:videoSettings];
//
//
//
//
//  AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
//                                                 assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoWriterInput
//                                                 sourcePixelBufferAttributes:nil];
//
//  NSParameterAssert(videoWriterInput);
//
//  NSParameterAssert([videoWriter canAddInput:videoWriterInput]);
//  videoWriterInput.expectsMediaDataInRealTime = YES;
//  [videoWriter addInput:videoWriterInput];
//  //Start a session:
//  [videoWriter startWriting];
//  [videoWriter startSessionAtSourceTime:kCMTimeZero];
//
//
//  //Video encoding
//
//  CVPixelBufferRef buffer = NULL;
//    NSArray m_PictArray = [NSArray array];
//
//  //convert uiimage to CGImage.
//
//  int frameCount = 0;
//
//  for(int i = 0; i<[m_PictArray count]; i++)
//  {
//    buffer = [self pixelBufferFromCGImage:[[m_PictArray objectAtIndex:i] CGImage] andSize:size];
//
//
//    BOOL append_ok = NO;
//    int j = 0;
//    while (!append_ok && j < 30)
//    {
//        if (adaptor.assetWriterInput.readyForMoreMediaData)
//        {
//            printf("appending %d attemp %d\n", frameCount, j);
//
//            CMTime frameTime = CMTimeMake(frameCount,(int32_t) 10);
//
//            append_ok = [adaptor appendPixelBuffer:buffer withPresentationTime:frameTime];
//            CVPixelBufferPoolRef bufferPool = adaptor.pixelBufferPool;
//            NSParameterAssert(bufferPool != NULL);
//
//            [NSThread sleepForTimeInterval:0.05];
//        }
//        else
//        {
//            printf("adaptor not ready %d, %d\n", frameCount, j);
//            [NSThread sleepForTimeInterval:0.1];
//        }
//        j++;
//    }
//    if (!append_ok)
//    {
//        printf("error appending image %d times %d\n", frameCount, j);
//    }
//    frameCount++;
//    CVBufferRelease(buffer);
//  }
//
//  [videoWriterInput markAsFinished];
//    [videoWriter finishWritingWithCompletionHandler:^{
//
//    }];
//
//  [m_PictArray removeAllObjects];
//
//  NSLog(@"Write Ended");
}

-(void)CompileFilesToMakeMovie
{
//  AVMutableComposition* mixComposition = [AVMutableComposition composition];
//
//  NSString* audio_inputFileName = @"deformed.caf";
//  NSString* audio_inputFilePath = [Utilities documentsPath:audio_inputFileName];
//  NSURL*    audio_inputFileUrl = [NSURL fileURLWithPath:audio_inputFilePath];
//
//  NSString* video_inputFileName = @"essai.mp4";
//  NSString* video_inputFilePath = [Utilities documentsPath:video_inputFileName];
//  NSURL*    video_inputFileUrl = [NSURL fileURLWithPath:video_inputFilePath];
//
//  NSString* outputFileName = @"outputFile.mov";
//  NSString* outputFilePath = [Utilities documentsPath:outputFileName];
//  NSURL*    outputFileUrl = [NSURL fileURLWithPath:outputFilePath];
//
//  if ([[NSFileManager defaultManager] fileExistsAtPath:outputFilePath])
//    [[NSFileManager defaultManager] removeItemAtPath:outputFilePath error:nil];
//
//
//
//  CMTime nextClipStartTime = kCMTimeZero;
//
//  AVURLAsset* videoAsset = [[AVURLAsset alloc]initWithURL:video_inputFileUrl options:nil];
//  CMTimeRange video_timeRange = CMTimeRangeMake(kCMTimeZero,videoAsset.duration);
//  AVMutableCompositionTrack *a_compositionVideoTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
//  [a_compositionVideoTrack insertTimeRange:video_timeRange ofTrack:[[videoAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0] atTime:nextClipStartTime error:nil];
//
//  //nextClipStartTime = CMTimeAdd(nextClipStartTime, a_timeRange.duration);
//
//  AVURLAsset* audioAsset = [[AVURLAsset alloc]initWithURL:audio_inputFileUrl options:nil];
//  CMTimeRange audio_timeRange = CMTimeRangeMake(kCMTimeZero, audioAsset.duration);
//  AVMutableCompositionTrack *b_compositionAudioTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
//  [b_compositionAudioTrack insertTimeRange:audio_timeRange ofTrack:[[audioAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0] atTime:nextClipStartTime error:nil];
//
//
//
//  AVAssetExportSession* _assetExport = [[AVAssetExportSession alloc] initWithAsset:mixComposition presetName:AVAssetExportPresetHighestQuality];
//  _assetExport.outputFileType = @"com.apple.quicktime-movie";
//  _assetExport.outputURL = outputFileUrl;
//
//  [_assetExport exportAsynchronouslyWithCompletionHandler:
// ^(void ) {
//     [self saveVideoToAlbum:outputFilePath];
// }
// ];
}

- (UIImage *)decodeBase64ToImage:(NSString *)strEncodeData {
  NSData *data = [[NSData alloc]initWithBase64EncodedString:strEncodeData options:NSDataBase64DecodingIgnoreUnknownCharacters];
  return [UIImage imageWithData:data];
}

@end
