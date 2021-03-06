/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"

typedef NSString * _Nullable(^SDWebImageCacheKeyFilterBlock)(NSURL * _Nonnull url);

// This is the protocol for cache key filter. We can use a block to specify the cache key filter. But Using protocol can make this extensible, and allow Swift user to use it easily instead of using `@convention(block)` to store a block into context options.
// 这是缓存密钥过滤器的协议。我们可以使用block来指定 缓存密钥过滤器。但是使用协议可以使这个可扩展，并允许Swift用户轻松使用它，而不是使用`@convention（block）`将块存储到上下文选项中。

@protocol SDWebImageCacheKeyFilter <NSObject>

- (nullable NSString *)cacheKeyForURL:(nonnull NSURL *)url;

@end

@interface SDWebImageCacheKeyFilter : NSObject <SDWebImageCacheKeyFilter>

- (nonnull instancetype)initWithBlock:(nonnull SDWebImageCacheKeyFilterBlock)block;
+ (nonnull instancetype)cacheKeyFilterWithBlock:(nonnull SDWebImageCacheKeyFilterBlock)block;

@end
