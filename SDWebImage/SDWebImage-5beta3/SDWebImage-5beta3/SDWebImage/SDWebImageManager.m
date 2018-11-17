/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageManager.h"
#import "SDImageCache.h"
#import "SDWebImageDownloader.h"
#import "UIImage+Metadata.h"
#import "SDWebImageError.h"

static id<SDImageCache> _defaultImageCache;
static id<SDImageLoader> _defaultImageLoader;

@interface SDWebImageCombinedOperation ()

@property (assign, nonatomic, getter = isCancelled) BOOL cancelled;
@property (strong, nonatomic, readwrite, nullable) id<SDWebImageOperation> loaderOperation;
@property (strong, nonatomic, readwrite, nullable) id<SDWebImageOperation> cacheOperation;
@property (weak, nonatomic, nullable) SDWebImageManager *manager;

@end

@interface SDWebImageManager ()

//管理缓存
@property (strong, nonatomic, readwrite, nonnull) SDImageCache *imageCache;
// 下载器*imageDownloader;
@property (strong, nonatomic, readwrite, nonnull) id<SDImageLoader> imageLoader;
// 记录失效url的名单
@property (strong, nonatomic, nonnull) NSMutableSet<NSURL *> *failedURLs;

// 一个锁以保证对“failedURLs”线程安全的访问
@property (strong, nonatomic, nonnull) dispatch_semaphore_t failedURLsLock; // a lock to keep the access to `failedURLs` thread-safe

// 记录当前正在执行的操作
@property (strong, nonatomic, nonnull) NSMutableSet<SDWebImageCombinedOperation *> *runningOperations;

// 一个锁，以保证对“runningOperations”线程安全的访问
@property (strong, nonatomic, nonnull) dispatch_semaphore_t runningOperationsLock; // a lock to keep the access to `runningOperations` thread-safe

@end

@implementation SDWebImageManager

+ (id<SDImageCache>)defaultImageCache {
    return _defaultImageCache;
}

+ (void)setDefaultImageCache:(id<SDImageCache>)defaultImageCache {
    if (defaultImageCache && ![defaultImageCache conformsToProtocol:@protocol(SDImageCache)]) {
        return;
    }
    _defaultImageCache = defaultImageCache;
}

+ (id<SDImageLoader>)defaultImageLoader {
    return _defaultImageLoader;
}

+ (void)setDefaultImageLoader:(id<SDImageLoader>)defaultImageLoader {
    if (defaultImageLoader && ![defaultImageLoader conformsToProtocol:@protocol(SDImageLoader)]) {
        return;
    }
    _defaultImageLoader = defaultImageLoader;
}

+ (nonnull instancetype)sharedManager {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (nonnull instancetype)init {
    id<SDImageCache> cache = [[self class] defaultImageCache];
    if (!cache) {
        cache = [SDImageCache sharedImageCache];
    }
    id<SDImageLoader> loader = [[self class] defaultImageLoader];
    if (!loader) {
        loader = [SDWebImageDownloader sharedDownloader];
    }
    return [self initWithCache:cache loader:loader];
}

- (nonnull instancetype)initWithCache:(nonnull id<SDImageCache>)cache loader:(nonnull id<SDImageLoader>)loader {
    if ((self = [super init])) {
        _imageCache = cache;
        _imageLoader = loader;
        _failedURLs = [NSMutableSet new];
        _failedURLsLock = dispatch_semaphore_create(1);
        _runningOperations = [NSMutableSet new];
        _runningOperationsLock = dispatch_semaphore_create(1);
    }
    return self;
}

- (nullable NSString *)cacheKeyForURL:(nullable NSURL *)url {
    return [self cacheKeyForURL:url cacheKeyFilter:self.cacheKeyFilter];
}

- (nullable NSString *)cacheKeyForURL:(nullable NSURL *)url cacheKeyFilter:(id<SDWebImageCacheKeyFilter>)cacheKeyFilter {
    if (!url) {
        return @"";
    }

    if (cacheKeyFilter) {
        return [cacheKeyFilter cacheKeyForURL:url];
    } else {
        return url.absoluteString;
    }
}

- (SDWebImageCombinedOperation *)loadImageWithURL:(NSURL *)url options:(SDWebImageOptions)options progress:(SDImageLoaderProgressBlock)progressBlock completed:(SDInternalCompletionBlock)completedBlock {
    return [self loadImageWithURL:url options:options context:nil progress:progressBlock completed:completedBlock];
}


/**
 <#Description#>

 @param url <#url description#>
 @param options <#options description#>
 @param context <#context description#>
 @param progressBlock <#progressBlock description#>
 @param completedBlock <#completedBlock description#>
 @return <#return value description#>
 */
- (SDWebImageCombinedOperation *)loadImageWithURL:(nullable NSURL *)url
                                          options:(SDWebImageOptions)options
                                          context:(nullable SDWebImageContext *)context
                                         progress:(nullable SDImageLoaderProgressBlock)progressBlock
                                        completed:(nonnull SDInternalCompletionBlock)completedBlock {
    // Invoking this method without a completedBlock is pointless
    // 在没有completedBlock的情况下调用此方法毫无意义
    NSAssert(completedBlock != nil, @"If you mean to prefetch the image, use -[SDWebImagePrefetcher prefetchURLs] instead");

    // Very common mistake is to send the URL using NSString object instead of NSURL. For some strange reason, Xcode won't
    // throw any warning for this type mismatch. Here we failsafe this error by allowing URLs to be passed as NSString.
    //很常见的错误是使用NSString对象而不是NSURL发送URL。出于某些奇怪的原因，Xcode不会对此类型不匹配发出任何警告。在这里，我们通过允许URL作为NSString传递来确保此错误。
    if ([url isKindOfClass:NSString.class]) {
        // 容错，强制转换类型
        url = [NSURL URLWithString:(NSString *)url];
    }

    // Prevents app crashing on argument type error like sending NSNull instead of NSURL
    // 防止应用程序崩溃类型错误，如发送NSNull而不是NSURL
    if (![url isKindOfClass:NSURL.class]) {
        url = nil;
    }

    SDWebImageCombinedOperation *operation = [SDWebImageCombinedOperation new];
    operation.manager = self;

    BOOL isFailedUrl = NO;
    if (url) {
        LOCK(self.failedURLsLock);
        isFailedUrl = [self.failedURLs containsObject:url];
        UNLOCK(self.failedURLsLock);
    }

    // url绝对路径为0 , 或者
    if (url.absoluteString.length == 0 || (!(options & SDWebImageRetryFailed) && isFailedUrl)) {
        [self callCompletionBlockForOperation:operation completion:completedBlock error:[NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorInvalidURL userInfo:@{NSLocalizedDescriptionKey : @"Image url is nil"}] url:url];
        return operation;
    }

    //给self.runningOperations加锁
    //self.runningOperations数组的添加操作
    LOCK(self.runningOperationsLock);
    [self.runningOperations addObject:operation];
    UNLOCK(self.runningOperationsLock);
    
    // Preprocess the context arg to provide the default value from manager
    // 预处理上下文arg 以提供manager的默认值
    context = [self processedContextWithContext:context];
    
    // Start the entry to load image from cache
    // 启动条目 从缓存加载图像
    [self callCacheProcessForOperation:operation url:url options:options context:context progress:progressBlock completed:completedBlock];

    return operation;
}



- (void)cancelAll {
    LOCK(self.runningOperationsLock);
    NSSet<SDWebImageCombinedOperation *> *copiedOperations = [self.runningOperations copy];
    UNLOCK(self.runningOperationsLock);
    [copiedOperations makeObjectsPerformSelector:@selector(cancel)]; // This will call `safelyRemoveOperationFromRunning:` and remove from the array
}

- (BOOL)isRunning {
    BOOL isRunning = NO;
    LOCK(self.runningOperationsLock);
    isRunning = (self.runningOperations.count > 0);
    UNLOCK(self.runningOperationsLock);
    return isRunning;
}

#pragma mark - Private
// SDWebImageManager  私有方法
- (void)callCacheProcessForOperation:(nonnull SDWebImageCombinedOperation *)operation
                                 url:(nullable NSURL *)url
                             options:(SDWebImageOptions)options
                             context:(nullable SDWebImageContext *)context
                            progress:(nullable SDImageLoaderProgressBlock)progressBlock
                           completed:(nullable SDInternalCompletionBlock)completedBlock {
    // Check whether we should query cache
    // 检查我们是否应该查询缓存
    BOOL shouldQueryCache = (options & SDWebImageFromLoaderOnly) == 0;
    // 如果shouldQueryCache为真 ,查询缓存
    if (shouldQueryCache) {
        id<SDWebImageCacheKeyFilter> cacheKeyFilter = context[SDWebImageContextCacheKeyFilter];
        NSString *key = [self cacheKeyForURL:url cacheKeyFilter:cacheKeyFilter];
        __weak SDWebImageCombinedOperation *weakOperation = operation;
        
        // 在SDImageCache里查询是否存在缓存的图片
        operation.cacheOperation = [self.imageCache queryImageForKey:key options:options context:context completion:^(UIImage * _Nullable cachedImage, NSData * _Nullable cachedData, SDImageCacheType cacheType) {
            __strong __typeof(weakOperation) strongOperation = weakOperation;
           
            if (!strongOperation || strongOperation.isCancelled) {
                // 1. 如果任务被取消，删除操作 SDWebImageCombinedOperation
                [self safelyRemoveOperationFromRunning:strongOperation];
                return;
            }
            
            // Continue download process
            //2. 如果有错误
            //2.1 在completedBlock里传入error
            [self callDownloadProcessForOperation:strongOperation url:url options:options context:context cachedImage:cachedImage cachedData:cachedData cacheType:cacheType progress:progressBlock completed:completedBlock];
        }];
    } else {
        
        // Continue download process
        // 将图片传入completedBlock
        [self callDownloadProcessForOperation:operation url:url options:options context:context cachedImage:nil cachedData:nil cacheType:SDImageCacheTypeNone progress:progressBlock completed:completedBlock];
    }
}

- (void)callDownloadProcessForOperation:(nonnull SDWebImageCombinedOperation *)operation
                                    url:(nullable NSURL *)url
                                options:(SDWebImageOptions)options
                                context:(SDWebImageContext *)context
                            cachedImage:(nullable UIImage *)cachedImage
                             cachedData:(nullable NSData *)cachedData
                              cacheType:(SDImageCacheType)cacheType
                               progress:(nullable SDImageLoaderProgressBlock)progressBlock
                              completed:(nullable SDInternalCompletionBlock)completedBlock {
   
    // Check whether we should download image from network
    // 有缓存图片 & 仅从缓存加载
    BOOL shouldDownload = (options & SDWebImageFromCacheOnly) == 0;
    // 没有缓存图片 || 即使有缓存图片，也需要更新缓存图片
    shouldDownload &= (!cachedImage || options & SDWebImageRefreshCached);
    // 代理没有响应imageManager:shouldDownloadImageForURL:消息，默认返回yes，需要下载图片 || mageManager:shouldDownloadImageForURL:返回yes，需要下载图片
    shouldDownload &= (![self.delegate respondsToSelector:@selector(imageManager:shouldDownloadImageForURL:)] || [self.delegate imageManager:self shouldDownloadImageForURL:url]);
    shouldDownload &= [self.imageLoader canLoadWithURL:url];
    
    if (shouldDownload) {
        
        //1. 存在缓存图片 && 即使有缓存图片也要下载更新图片
        if (cachedImage && options & SDWebImageRefreshCached) {
            // If image was found in the cache but SDWebImageRefreshCached is provided, notify about the cached image
            // AND try to re-download it in order to let a chance to NSURLCache to refresh it from server.
            //如果在缓存中找到了图像但提供了SDWebImageRefreshCached，则通知缓存图像
            //并尝试重新下载它，以便让NSURLCache有机会从服务器刷新它。
            [self callCompletionBlockForOperation:operation completion:completedBlock image:cachedImage data:cachedData error:nil cacheType:cacheType finished:YES url:url];
            
            // Pass the cached image to the image loader. The image loader should check whether the remote image is equal to the cached image.
            // 将缓存的图像传递给图像加载器。图像加载器应检查远程图像是否等于缓存图像。
            SDWebImageMutableContext *mutableContext;
            if (context) {
                mutableContext = [context mutableCopy];
            } else {
                mutableContext = [NSMutableDictionary dictionary];
            }
            mutableContext[SDWebImageContextLoaderCachedImage] = cachedImage;
            context = [mutableContext copy];
        }
        
        // `SDWebImageCombinedOperation` -> `SDWebImageDownloadToken` -> `downloadOperationCancelToken`, which is a `SDCallbacksDictionary` and retain the completed block below, so we need weak-strong again to avoid retain cycle
        //`SDWebImageCombinedOperation`  - >`SDWebImageDownloadToken`  - >`downloadOperationCancelToken`，这是一个`SDCallbacksDictionary`并保留下面的完整块，所以我们需要使用 weak-strong 以避免retain 循环
        __weak typeof(operation) weakOperation = operation;
        operation.loaderOperation = [self.imageLoader loadImageWithURL:url options:options context:context progress:progressBlock completed:^(UIImage *downloadedImage, NSData *downloadedData, NSError *error, BOOL finished) {
            __strong typeof(weakOperation) strongOperation = weakOperation;
            
            if (!strongOperation || strongOperation.isCancelled) {
                // Do nothing if the operation was cancelled 如果取消操作，则不执行任何操作
                // See #699 for more details
                // if we would call the completedBlock, there could be a race condition between this block and another completedBlock for the same object, so if this one is called second, we will overwrite the new data
                //如果我们要调用completedBlock，那么这个block 和 同一个对象的另一个completedBlock 之间可能存在重复冲突，所以如果这个被第二次调用，我们将覆盖新数据
                
            } else if (cachedImage && options & SDWebImageRefreshCached && [error.domain isEqualToString:SDWebImageErrorDomain] && error.code == SDWebImageErrorCacheNotModified) {
                // Image refresh hit the NSURLCache cache, do not call the completion block
                // image刷新 命中 NSURLCache缓存，不调用completion block
            } else if (error) {
                //2. 如果有错误
                //2.1 在completedBlock里传入error
                [self callCompletionBlockForOperation:strongOperation completion:completedBlock error:error url:url];
                BOOL shouldBlockFailedURL;
                // Check whether we should block failed url
                //
                if ([self.delegate respondsToSelector:@selector(imageManager:shouldBlockFailedURL:withError:)]) {
                    shouldBlockFailedURL = [self.delegate imageManager:self shouldBlockFailedURL:url withError:error];
                } else {
                    //2.2 在错误url名单中添加当前的url
                    shouldBlockFailedURL = (   error.code != NSURLErrorNotConnectedToInternet
                                            && error.code != NSURLErrorCancelled
                                            && error.code != NSURLErrorTimedOut
                                            && error.code != NSURLErrorInternationalRoamingOff
                                            && error.code != NSURLErrorDataNotAllowed
                                            && error.code != NSURLErrorCannotFindHost
                                            && error.code != NSURLErrorCannotConnectToHost
                                            && error.code != NSURLErrorNetworkConnectionLost);
                }
                
                if (shouldBlockFailedURL) {
                    LOCK(self.failedURLsLock);
                    [self.failedURLs addObject:url];
                    UNLOCK(self.failedURLsLock);
                }
            } else {
                
                //3. 下载成功
                //3.1 如果需要下载失败后重新下载，则将当前url从失败url名单里移除
                if ((options & SDWebImageRetryFailed)) {
                    LOCK(self.failedURLsLock);
                    [self.failedURLs removeObject:url];
                    UNLOCK(self.failedURLsLock);
                }
                
                SDImageCacheType storeCacheType = SDImageCacheTypeAll;
                if (context[SDWebImageContextStoreCacheType]) {
                    storeCacheType = [context[SDWebImageContextStoreCacheType] integerValue];
                }
                id<SDWebImageCacheKeyFilter> cacheKeyFilter = context[SDWebImageContextCacheKeyFilter];
                NSString *key = [self cacheKeyForURL:url cacheKeyFilter:cacheKeyFilter];
                id<SDImageTransformer> transformer = context[SDWebImageContextImageTransformer];
                id<SDWebImageCacheSerializer> cacheSerializer = context[SDWebImageContextCacheSerializer];
                
                //
                if (downloadedImage && (!downloadedImage.sd_isAnimated || (options & SDWebImageTransformAnimatedImage)) && transformer) {
                    
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                        UIImage *transformedImage = [transformer transformedImageWithImage:downloadedImage forKey:key];
                        if (transformedImage && finished) {
                            NSString *transformerKey = [transformer transformerKey];
                            NSString *cacheKey = SDTransformedKeyForKey(key, transformerKey);
                            BOOL imageWasTransformed = ![transformedImage isEqual:downloadedImage];
                            NSData *cacheData;
                            // pass nil if the image was transformed, so we can recalculate the data from the image
                            // 如果图片被转换，则传递nil，因此我们可以重新计算图像中的数据
                            if (cacheSerializer) {
                                cacheData = [cacheSerializer cacheDataWithImage:transformedImage  originalData:(imageWasTransformed ? nil : downloadedData) imageURL:url];
                            } else {
                                cacheData = (imageWasTransformed ? nil : downloadedData);
                            }
                            // 缓存图片
                            [self.imageCache storeImage:transformedImage imageData:cacheData forKey:cacheKey cacheType:storeCacheType completion:nil];
                        }
                        
                        // 将图片传入completedBlock
                        [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:transformedImage data:downloadedData error:nil cacheType:SDImageCacheTypeNone finished:finished url:url];
                    });
                } else {
                    // (图片下载成功并结束)
                    if (downloadedImage && finished) {
                        if (cacheSerializer) {
                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                                NSData *cacheData = [cacheSerializer cacheDataWithImage:downloadedImage originalData:downloadedData imageURL:url];
                                [self.imageCache storeImage:downloadedImage imageData:cacheData forKey:key cacheType:storeCacheType completion:nil];
                            });
                        } else {

                            [self.imageCache storeImage:downloadedImage imageData:downloadedData forKey:key cacheType:storeCacheType completion:nil];
                        }
                    }
                    
                    // 调用完成的block
                    [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:downloadedImage data:downloadedData error:nil cacheType:SDImageCacheTypeNone finished:finished url:url];
                }
            }
            
            //如果完成，从当前运行的操作列表里移除当前操作
            if (finished) {
                [self safelyRemoveOperationFromRunning:strongOperation];
            }
        }];
    } else if (cachedImage) { // 存在缓存图片

        // 调用完成的block
        [self callCompletionBlockForOperation:operation completion:completedBlock image:cachedImage data:cachedData error:nil cacheType:cacheType finished:YES url:url];
        // 删去当前的的下载操作（线程安全）
        [self safelyRemoveOperationFromRunning:operation];
    } else {
        // Image not in cache and download disallowed by delegate
        // 没有缓存的图片，而且下载被代理终止了
        // 调用完成的block
        [self callCompletionBlockForOperation:operation completion:completedBlock image:nil data:nil error:nil cacheType:SDImageCacheTypeNone finished:YES url:url];
        // 删去当前的下载操作
        [self safelyRemoveOperationFromRunning:operation];
    }
}

#pragma mark - Helper
/* self.runningOperations数组的删除操作 */
- (void)safelyRemoveOperationFromRunning:(nullable SDWebImageCombinedOperation*)operation {
    if (!operation) {
        return;
    }
    
    // 数组的写操作需要加锁（多线程访问，避免覆写）
    LOCK(self.runningOperationsLock);
    //self.runningOperations数组的删除操作
    [self.runningOperations removeObject:operation];
    UNLOCK(self.runningOperationsLock);
}

- (void)callCompletionBlockForOperation:(nullable SDWebImageCombinedOperation*)operation
                             completion:(nullable SDInternalCompletionBlock)completionBlock
                                  error:(nullable NSError *)error
                                    url:(nullable NSURL *)url {
    [self callCompletionBlockForOperation:operation completion:completionBlock image:nil data:nil error:error cacheType:SDImageCacheTypeNone finished:YES url:url];
}

- (void)callCompletionBlockForOperation:(nullable SDWebImageCombinedOperation*)operation
                             completion:(nullable SDInternalCompletionBlock)completionBlock
                                  image:(nullable UIImage *)image
                                   data:(nullable NSData *)data
                                  error:(nullable NSError *)error
                              cacheType:(SDImageCacheType)cacheType
                               finished:(BOOL)finished
                                    url:(nullable NSURL *)url {
    dispatch_main_async_safe(^{
        if (operation && !operation.isCancelled && completionBlock) {
            completionBlock(image, data, error, cacheType, finished, url);
        }
    });
}

- (SDWebImageContext *)processedContextWithContext:(SDWebImageContext *)context {
    SDWebImageMutableContext *mutableContext = [SDWebImageMutableContext dictionary];
    
    // Image Transformer from manager
    //
    if (!context[SDWebImageContextImageTransformer]) {
        id<SDImageTransformer> transformer = self.transformer;
        [mutableContext setValue:transformer forKey:SDWebImageContextImageTransformer];
    }
    // Cache key filter from manager
    // 从经理缓存密钥过滤器
    if (!context[SDWebImageContextCacheKeyFilter]) {
        id<SDWebImageCacheKeyFilter> cacheKeyFilter = self.cacheKeyFilter;
        [mutableContext setValue:cacheKeyFilter forKey:SDWebImageContextCacheKeyFilter];
    }
    // Cache serializer from manager
    // 缓存序列化器
    if (!context[SDWebImageContextCacheSerializer]) {
        id<SDWebImageCacheSerializer> cacheSerializer = self.cacheSerializer;
        [mutableContext setValue:cacheSerializer forKey:SDWebImageContextCacheSerializer];
    }
    
    if (mutableContext.count == 0) {
        return context;
    } else {
        [mutableContext addEntriesFromDictionary:context];
        return [mutableContext copy];
    }
}

@end


@implementation SDWebImageCombinedOperation

- (void)cancel {
    @synchronized(self) {
        if (self.isCancelled) {
            return;
        }
        self.cancelled = YES;
        if (self.cacheOperation) {
            [self.cacheOperation cancel];
            self.cacheOperation = nil;
        }
        if (self.loaderOperation) {
            [self.loaderOperation cancel];
            self.loaderOperation = nil;
        }
        [self.manager safelyRemoveOperationFromRunning:self];
    }
}

@end
