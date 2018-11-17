/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIView+WebCacheOperation.h"
#import "objc/runtime.h"

static char loadOperationKey;

// key is strong, value is weak because operation instance is retained by SDWebImageManager's runningOperations property
// we should use lock to keep thread-safe because these method may not be acessed from main queue
typedef NSMapTable<NSString *, id<SDWebImageOperation>> SDOperationsDictionary;

@implementation UIView (WebCacheOperation)

//获取关联对象：operations（用来存放操作的字典）
//字典operationDictionary专门用作存储操作的缓存，随时添加，删除操作任务。它的存取方法使用运行时来操作
//为什么不直接在UIImageView+WebCache里直接关联这个对象呢？我觉得这里作者应该是遵从面向对象的单一职责原则（SRP：Single responsibility principle），就连类都要履行这个职责，何况分类呢？这里作者专门创造一个分类UIView+WebCacheOperation来管理操作缓存（字典）。

- (SDOperationsDictionary *)sd_operationDictionary {
    @synchronized(self) {
        //运行时存取关联对象: 取,将operations对象通过地址&loadOperationKey从self里取出来
        SDOperationsDictionary *operations = objc_getAssociatedObject(self, &loadOperationKey);
        //存放操作的字典
        if (operations) {
            return operations;
        }
        //如果没有，就新建一个
        operations = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory capacity:0];
        
        //运行时存取关联对象:存, 将operations对象关联给self，地址为&loadOperationKey，语义是OBJC_ASSOCIATION_RETAIN_NONATOMIC。
        objc_setAssociatedObject(self, &loadOperationKey, operations, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return operations;
    }
}

- (nullable id<SDWebImageOperation>)sd_imageLoadOperationForKey:(nullable NSString *)key  {
    id<SDWebImageOperation> operation;
    if (key) {
        SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];
        @synchronized (self) {
            operation = [operationDictionary objectForKey:key];
        }
    }
    return operation;
}

- (void)sd_setImageLoadOperation:(nullable id<SDWebImageOperation>)operation forKey:(nullable NSString *)key {
    if (key) {
        [self sd_cancelImageLoadOperationWithKey:key];
        if (operation) {
            SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];
            @synchronized (self) {
                [operationDictionary setObject:operation forKey:key];
            }
        }
    }
}

- (void)sd_cancelImageLoadOperationWithKey:(nullable NSString *)key {
    if (key) {
        // Cancel in progress downloader from queue
        SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];
        id<SDWebImageOperation> operation;
        
        @synchronized (self) {
            operation = [operationDictionary objectForKey:key];
        }
        if (operation) {
            if ([operation conformsToProtocol:@protocol(SDWebImageOperation)]) {
                [operation cancel];
            }
            @synchronized (self) {
                [operationDictionary removeObjectForKey:key];
            }
        }
    }
}

- (void)sd_removeImageLoadOperationWithKey:(nullable NSString *)key {
    if (key) {
        SDOperationsDictionary *operationDictionary = [self sd_operationDictionary];
        @synchronized (self) {
            [operationDictionary removeObjectForKey:key];
        }
    }
}

@end
