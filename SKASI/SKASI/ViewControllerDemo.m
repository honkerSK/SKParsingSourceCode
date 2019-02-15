//
//  ViewControllerDemo.m
//  SKASI
//
//  Created by sunke on 22/11/2018.
//  Copyright © 2018 sunke. All rights reserved.
//

#import "ViewControllerDemo.h"
#import "ASIHTTPRequest.h"

// ASI同步请求和3种异步请求
@interface ViewControllerDemo ()<ASIHTTPRequestDelegate>

@end

@implementation ViewControllerDemo

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self asyncSelectorDemo];
}

#pragma mark - 异步请求
#pragma mark 异步请求3-自行指定网络监听方法(知道就行)
- (void)asyncSelectorDemo {
    // 1. url
    NSURL *url = [NSURL URLWithString:@"http://192.168.31.2/videos.json"];
    
    // 2. 请求
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
    
    // 指定监听方法 － 接收到服务器的响应头方法没有指定，如果程序中实现，会同样会被调用！
    // 开始的方法
    [request setDidStartSelector:@selector(start:)];
    // 完成的监听
    [request setDidFinishSelector:@selector(finished:)];
    // 失败的监听
    [request setDidFailSelector:@selector(failed:)];
    
    // 需要注意的，以上方法是在修改代理监听的执行方法
    // 需要指定代理
    request.delegate = self;
    
    // 3. 启动请求
    [request startAsynchronous];
}

- (void)start:(ASIHTTPRequest *)request {
    NSLog(@"%s %@", __FUNCTION__, request);
}

- (void)finished:(ASIHTTPRequest *)request {
    NSLog(@"%s %@", __FUNCTION__, request);
}

- (void)failed:(ASIHTTPRequest *)request {
    NSLog(@"%s %@", __FUNCTION__, request);
}

#pragma mark 异步请求2-通过块代码来监听网络请求
- (void)asyncBlockDemo {
    // 1. url
    NSURL *url = [NSURL URLWithString:@"http://192.168.31.2/videos.json"];
    
    // 2. 请求
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
    
    // 设置代理
    request.delegate = self;
    
    // 2.1 块代码回调
    // 开始
    [request setStartedBlock:^{
        NSLog(@"start");
    }];
    // 接收到响应头
    [request setHeadersReceivedBlock:^(NSDictionary *responseHeaders) {
        NSLog(@"block - %@", responseHeaders);
    }];
    
    // 接收到字节（下载）
    //    request setBytesReceivedBlock:^(unsigned long long size, unsigned long long total) {
    //
    //    }
    // 接收到数据，和代理方法一样，一旦设置，在网络完成时，就没有办法获得结果
    // 实现这个方法，就意味着程序员自己处理每次接收到的二进制数据！
    //    [request setDataReceivedBlock:^(NSData *data) {
    //        NSLog(@"%@", data);
    //    }];
    
    // 简单的网络访问
    __weak typeof(request) weakRequest = request;
    [request setCompletionBlock:^{
        NSLog(@"block - %@", weakRequest.responseString);
    }];
    // 访问出错
    [request setFailedBlock:^{
        NSLog(@"block - %@", weakRequest.error);
    }];
    
    // 3. 发起异步
    [request startAsynchronous];
}

/**
 在 ASI 中，异步请求，有三种方式能够“监听”到！
 */
- (void)asyncDemo {
    // 1. url
    NSURL *url = [NSURL URLWithString:@"http://192.168.31.2/videos.json"];
    
    // 2. request
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
    
    // 设置代理
    request.delegate = self;
    
    // 3. 启动异步
    [request startAsynchronous];
}

#pragma mark 异步请求1-代理方法
// 开发多线程框架的时候，有一个细节
// 耗时的操作，框架来做，在后台线程，回调方法在主线程做，使用框架的人，不需要关心线程间通讯
- (void)requestStarted:(ASIHTTPRequest *)request {
    NSLog(@"%s", __FUNCTION__);
}

- (void)request:(ASIHTTPRequest *)request didReceiveResponseHeaders:(NSDictionary *)responseHeaders {
    NSLog(@"%s %@", __FUNCTION__, responseHeaders);
}

- (void)requestFinished:(ASIHTTPRequest *)request {
    NSLog(@"%s %@ %@", __FUNCTION__, request.responseString, [NSThread currentThread]);
}

- (void)requestFailed:(ASIHTTPRequest *)request {
    NSLog(@"失败 %@", request.error);
}

// 此方法知道就行，一旦实现了这个方法，那么在 requestFinished 方法中，就得不到最终的结果了！
//- (void)request:(ASIHTTPRequest *)request didReceiveData:(NSData *)data {
//    NSLog(@"%s %@", __FUNCTION__, data);
//}

#pragma mark - 同步请求
- (void)syncDemo {
    /**
     问题：
     1. 只要是网络访问，就有可能出错！
     2. 超时时长！
     3. 多线程！
     */
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        // 1. url
        NSURL *url = [NSURL URLWithString:@"http://192.168.31.2/videos.json"];
        
        // 2. 请求
        ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
        
        // 修改网络请求超时时长
        // 默认的网络请求超时时长 10 秒，苹果官方的是 60 秒，SDWebImage 是 15 秒，AFN 是 60 秒
        request.timeOutSeconds = 2.0;
        // 这种方法在开发中很少用，因为不能指定时长60
        // 这种方法不能处理错误，只能根据data是否存在，判断网络请求是否出错！
        //        NSData *data = [NSData dataWithContentsOfURL:url];
        
        // 3. 同步启动请求，会阻塞当前线程
        [request startSynchronous];
        
        // 出错处理
        if (request.error) {
            NSLog(@"%@", request.error);
            return;
        }
        
        // 4. 就能够拿到响应的结果
        NSLog(@"%@ %@", request.responseData, [NSThread currentThread]);
        
        // 5. 如果返回的内容确实是字符串，可以使用 responseString
        NSLog(@"%@ %@", request.responseString, [NSThread currentThread]);
        
        //    NSString *str = [[NSString alloc] initWithData:request.responseData encoding:NSUTF8StringEncoding];
        //    NSLog(@"%@", str);
    });
}



@end
