//
//  ViewController.m
//  AVBugTest
//
//  Created by Alexander Gingell on 05/07/2017.
//  Copyright © 2017 Horsie in the Hedge LLP. All rights reserved.
//

#import "ViewController.h"
@import Photos;
@import AVFoundation;

@interface ViewController ()

@property (strong, nonatomic) IBOutlet UIImageView *imageView;
@property (strong, nonatomic) NSNumber *videoBitrate;

@property (strong, nonatomic) __block AVAssetWriter *writer;
@property (strong, nonatomic) __block AVAssetWriterInput *writerInput;
@property (strong, nonatomic) __block AVAssetWriterInputPixelBufferAdaptor *adaptor;
@property (strong, nonatomic) NSURL *writerVideoURL;
@property (strong, nonatomic) NSString *writerVideoPath;
@property (nonatomic) CGFloat writerVideoDuration;
@property (nonatomic) CGFloat writerVideoFrameRate;
@property (nonatomic) CGSize writerVideoFrameSize;
@property (nonatomic) NSInteger writerVideoFrameCount;
@property (strong, nonatomic) dispatch_queue_t renderQueueSerial;

@end

static NSString * const kAppName = @"AVBugTest";

@implementation ViewController

- (void) awakeFromNib
{
    [super awakeFromNib];
    self.renderQueueSerial = dispatch_queue_create("AVBugTest.SerialQueue", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(self.renderQueueSerial, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0ul));
    [self setVideoBitrate:@(15000000)]; // 15 Mbps;
}

- (void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.imageView setImage:[self imageForFrame:0]];
}

- (IBAction)buttonTouchUpInside:(id)sender
{
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusAuthorized)
    {
        dispatch_async(self.renderQueueSerial, ^{ [self render]; });
    }
    else if (status == PHAuthorizationStatusNotDetermined)
    {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            
            if (status == PHAuthorizationStatusAuthorized) {
                dispatch_async(self.renderQueueSerial, ^{ [self render]; });
            }
        }];
    }
}

#pragma mark - Rendering

- (void) render
{
    NSUInteger frameCount = 48;
    int32_t fps = (int32_t)24;
    
    // Start the asset writer
    [self startAssetWriterWithVideoDuration:2.0f // seconds
                                  frameSize:CGSizeMake(640, 640)
                                  frameRate:24 // frames per second
                                 frameCount:frameCount];
    
    // Loop through frames appending as we go
    for (int frame = 0; frame < frameCount; frame++)
    {
        @autoreleasepool
        {
            UIImage *image = [self imageForFrame:frame];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.imageView setImage:image];
            });
            
            while (![self isReadyForNextFrame]) {}
            [self appendImage:image atFrame:frame frameRate:fps];
        }
    }
    
    // Complete asset writing
    [self completeAssetWriting];
}

#pragma mark - Asset Writing

- (BOOL) startAssetWriterWithVideoDuration:(CGFloat)duration
                                 frameSize:(CGSize)frameSize
                                 frameRate:(CGFloat)frameRate
                                frameCount:(NSInteger)frameCount
{
    // Remove references to any older assets and set variables
    NSError *error = nil;
    self.writerVideoDuration = duration;
    self.writerVideoFrameSize = frameSize;
    self.writerVideoFrameRate = frameRate;
    self.writerVideoFrameCount = frameCount;
    self.writerVideoPath = [self encodingPathBaseMov];
    self.writerVideoURL = [NSURL fileURLWithPath:self.writerVideoPath];
    if (self.writerVideoPath)
    {
        // Initialise AVAssetWriter
        [self clearFilePath:self.writerVideoPath]; // If this fails we'll try to overwrite anyway
        self.writer = [[AVAssetWriter alloc] initWithURL:self.writerVideoURL
                                                fileType:AVFileTypeQuickTimeMovie
                                                   error:&error];
        if (!error)
        {
            NSString * codecType; if (@available(iOS 11.0, *)) { codecType = AVVideoCodecTypeH264;} else { codecType = AVVideoCodecH264;}
            NSInteger frameWidth = (NSInteger)frameSize.width, frameHeight = (NSInteger)frameSize.height;
            NSDictionary *videoSettings = @{AVVideoCodecKey : codecType,
                                            AVVideoWidthKey : @(frameWidth),
                                            AVVideoHeightKey : @(frameHeight),
                                            AVVideoCompressionPropertiesKey : @{AVVideoAverageBitRateKey : self.videoBitrate}
                                            };
            
            self.writerInput = [AVAssetWriterInput
                                assetWriterInputWithMediaType:AVMediaTypeVideo
                                outputSettings:videoSettings];
            
            NSDictionary *attributes = @{(NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32ARGB),
                                         (NSString *)kCVPixelBufferWidthKey : @(frameWidth),
                                         (NSString *)kCVPixelBufferHeightKey : @(frameHeight),
                                         (NSString *)kCVPixelBufferCGImageCompatibilityKey : @YES,
                                         (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                                         };
            
            self.adaptor =  [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.writerInput
                                                                                             sourcePixelBufferAttributes:attributes];
            //NSParameterAssert(writerInput); // Debug
            //NSParameterAssert([videoWriter canAddInput:writerInput]); // Debug
            if ([self.writer canAddInput:self.writerInput])
            {
                [self.writer addInput:self.writerInput];
                self.writerInput.expectsMediaDataInRealTime = YES; // "Fixes all errors"
                
                // Start videoWriter session
                [self.writer startWriting];
                [self.writer startSessionAtSourceTime:kCMTimeZero];
                if ([self.writer status] != AVAssetWriterStatusFailed)
                {
                    return YES;
                }
            }
        }
    }
    
    // Something failed
    return NO;
}

- (BOOL) isReadyForNextFrame
{
    return self.adaptor.assetWriterInput.readyForMoreMediaData;
}

- (BOOL) appendImage:(UIImage *)image atFrame:(int)frame frameRate:(int32_t)frameRate
{
    NSLog(@"Appending image %@ at frame %zd (%zd fps)",image? NSStringFromCGSize(image.size) : @"NIL", frame, frameRate);
    BOOL didAppendSuccessfully = YES;
    
    // Get pixel buffer
    CVPixelBufferRef pxBuffer = NULL;
    CVPixelBufferPoolCreatePixelBuffer (kCFAllocatorDefault, self.adaptor.pixelBufferPool, &pxBuffer); // Get a pixel buffer from the pool
    // CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(imageRef), CGImageGetHeight(imageRef), kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef) options, &pxbuffer); // Alternative - create a new pixel buffer each time
    CVPixelBufferLockBaseAddress(pxBuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxBuffer);
    //NSParameterAssert(pxdata != NULL); // Debug
    
    // Draw image into pixel buffer
    CGImageRef imageRef = image.CGImage; // We don't own this CGImageRef and therefore don't need to release it.
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, CGImageGetWidth(imageRef), CGImageGetHeight(imageRef),
                                                 8, 4*CGImageGetWidth(imageRef), rgbColorSpace,
                                                 (CGBitmapInfo)kCGImageAlphaNoneSkipFirst);
    //NSParameterAssert(context); // Debug
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(imageRef), CGImageGetHeight(imageRef)), imageRef);
    //CGColorSpaceRelease(rgbColorSpace);  // Don't release if using static WERBUtility CGColorSpaceRef
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pxBuffer, 0);
    
    // Append pixel data to writer
    CMTime sourceTime = CMTimeMake((int64_t)frame, frameRate);
    if (!pxBuffer || ![self.adaptor appendPixelBuffer:pxBuffer withPresentationTime:sourceTime])
    {
        // Alert user
        NSLog(@"[Encoder] appendImage: failed to append pixel buffer. Pixel buffer:%@ asset writer error:%@",(pxBuffer == NULL)?@"NULL":@"OK",[self.writer error]);
        didAppendSuccessfully = NO;
    }
    
    // Release / return pixel buffer
    if(pxBuffer)
    {
        CVPixelBufferRelease(pxBuffer);
        pxBuffer = NULL;
    }
    
    return didAppendSuccessfully;
}

- (void) completeAssetWriting
{
    // Finalise writer
    [self.writerInput markAsFinished];
    
    __weak typeof(self) weakSelf = self;
    [self.writer finishWritingWithCompletionHandler:^{
        
        // Move video to app collection
        [self writeVideoAtFileURL:self.writerVideoURL toAppCollectionWithCompletionHandler:nil];
        
        // Release CVPixelBufferPool
        CVPixelBufferPoolRelease(weakSelf.adaptor.pixelBufferPool);
        
        // Purge writer references
        [weakSelf purgeWriter];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Finished writing video"
                                                                           message:@"Video should be in photo library - does it look correct?"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            }]];
            if ([alert respondsToSelector:@selector(popoverPresentationController)]) // iPad
            {
                [alert.popoverPresentationController setSourceView:self.view];
            }
            [self presentViewController:alert animated:YES completion:nil];
        });
    }];
}

- (void) purgeWriter
{
    self.writer = nil;
    self.writerInput = nil;
    self.adaptor = nil;
    self.writerVideoPath = nil;
    self.writerVideoURL = nil;
}

#pragma mark - Photo Kit

- (void) appAssetCollectionUsingSuccessBlock:(void (^)(PHAssetCollection *appAssetCollection))successBlock
{
    // Find the album
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.predicate = [NSPredicate predicateWithFormat:@"title = %@", kAppName];
    __block PHAssetCollection *collection = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                                                                                     subtype:PHAssetCollectionSubtypeAny
                                                                                     options:fetchOptions].firstObject;
    if (collection)
    {
        if (successBlock) { successBlock(collection); }
    }
    else
    {
        // Create app asset collection
        __block PHObjectPlaceholder *collectionPlaceholder = [PHObjectPlaceholder new];
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCollectionChangeRequest *creationRequest = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:kAppName];
            collectionPlaceholder = creationRequest.placeholderForCreatedAssetCollection;
        }
                                          completionHandler:^(BOOL success, NSError *error) {
                                              
                                              if (success)
                                              {
                                                  PHFetchResult *fetchResult = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[collectionPlaceholder.localIdentifier] options:nil];
                                                  collection = fetchResult.firstObject;
                                                  
                                                  if (collection && successBlock)
                                                  {
                                                      successBlock(collection);
                                                  }
                                              }
                                              else
                                              {
                                                  NSLog(@"Error creating app collection: %@",error.localizedDescription);
                                                  if (successBlock) { successBlock(nil); } // Should just write to camera roll
                                              }
                                          }];
    }
}

- (void) writeVideoAtFileURL:(NSURL *)fileURL toAppCollectionWithCompletionHandler:(void (^)(PHAsset *asset, NSURL *assetURL, NSError *error))completionHandler
{
    [self appAssetCollectionUsingSuccessBlock:^(PHAssetCollection *appAssetCollection) {
        
        // Create assset
        __block PHObjectPlaceholder *assetPlaceholder = [PHObjectPlaceholder new];
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetChangeRequest *creationRequest = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
            assetPlaceholder = creationRequest.placeholderForCreatedAsset;
        }
                                          completionHandler:^(BOOL assetCreated, NSError *error) {
                                              if (assetCreated)
                                              {
                                                  // Add to collection
                                                  [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                                                      PHAssetCollectionChangeRequest *albumChangeRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:appAssetCollection];
                                                      [albumChangeRequest addAssets:@[assetPlaceholder]];
                                                  }
                                                                                    completionHandler:^(BOOL addedToCollection, NSError *error) {
                                                                                        
                                                                                        // Fetch variables for completion handler (whether added to collection or not)
                                                                                        PHFetchResult *fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[assetPlaceholder.localIdentifier] options:nil];
                                                                                        PHAsset *asset = fetchResult.firstObject;
                                                                                        NSURL *assetURL = nil;
                                                                                        
                                                                                        if (asset)
                                                                                        {
                                                                                            // Generate assetURL from PHAsset, because ALAssetLibrary framework is legacy.
                                                                                            NSString *assetURLstring = @"assets-library://asset/asset.mov?id=";
                                                                                            NSString *identifier = asset.localIdentifier;
                                                                                            identifier = [[[identifier componentsSeparatedByString:@"/"] firstObject] stringByAppendingString:@"&ext=MOV"];
                                                                                            assetURLstring = [assetURLstring stringByAppendingString:identifier];
                                                                                            assetURL = [NSURL URLWithString:assetURLstring];
                                                                                        }
                                                                                        
                                                                                        if (completionHandler) { completionHandler(asset,assetURL,error); }
                                                                                    }];
                                              }
                                              else
                                              {
                                                  // Failed to create asset
                                                  if (completionHandler) { completionHandler(nil,nil,error); }
                                              }
                                          }];
    }];
}

#pragma mark - File System

// Helper for the test
- (UIImage *) imageForFrame:(NSUInteger)frame
{
    frame = MIN(MAX(frame, 0), 47);
    NSString *filename = [NSString stringWithFormat:@"TestSeq_%zd.jpg",frame];
    UIImage *image = [UIImage imageNamed:filename]; // Quick and dirty (cached unnecessarily) for testing purposes
    return image;
}

- (NSString *) encodingPathBaseMov
{
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"Test.mov"];
}

- (BOOL) clearFilePath:(NSString *)path
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path])
    {
        return [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    else
    {
        return YES;
    }
}

@end
