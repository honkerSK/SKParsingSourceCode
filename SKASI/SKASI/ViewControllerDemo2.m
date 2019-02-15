//
//  ViewControllerDemo2.m
//  SKASI
//
//  Created by sunke on 22/11/2018.
//  Copyright © 2018 sunke. All rights reserved.
//

#import "ViewControllerDemo2.h"
#import "ASIHTTPRequest.h"
#import "ASIFormDataRequest.h"

@interface ViewControllerDemo2 ()<ASIHTTPRequestDelegate, ASIProgressDelegate>

@property (weak, nonatomic) IBOutlet UIProgressView *progressView;
@property (nonatomic, strong) ASIHTTPRequest *request;

@end

@implementation ViewControllerDemo2

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self download];
}

- (void)dealloc {
    // 取消下载任务
    [self.request clearDelegatesAndCancel];
}

#pragma mark - 下载
- (void)download {
    NSString *urlString = @"http://192.168.31.2/简介.mp4";
    urlString = [urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURL *url = [NSURL URLWithString:urlString];
    
    // 请求
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
    
    // 下载需要指定下载的路径(缓存路径)
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
    cacheDir = [cacheDir stringByAppendingPathComponent:@"321.mp4"];
    NSLog(@"%@", cacheDir);
    
    // 1.------------------------------------------------------------
    // 设置保存下载文件的目标路径！
    // !!! 一定要指定文件名，如果指定的是桌面，桌面上的所有文件都会消失！
    [request setDownloadDestinationPath:cacheDir];
    
    // 2.------------------------------------------------------------
    // 断点续传
    [request setAllowResumeForFileDownloads:YES];
    // 需要设置临时文件（包含文件名的全路径）
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"aaa.tmp"];
    [request setTemporaryFileDownloadPath:tmpPath];
    
    // 3.------------------------------------------------------------
    // 下载进度跟进
    //    request.downloadProgressDelegate = self;
    // 进度跟进的代理！！！
    // 设置代理， id <遵守某一个协议> delegate;
    // 设置代理， id delegate;对象不必遵守指定的协议，但是当发生事件的时候，同样会通知代理执行相关的方法！
    // 当进度发生变化是，给进度视图发送 setProgress 消息！
    request.downloadProgressDelegate = self.progressView;
    
    // 设置完成块
    [request setCompletionBlock:^{
        NSLog(@"OK");
    }];
    
    self.request = request;
    
    [request startAsynchronous];
}

//// 进度的代理方法
//- (void)setProgress:(float)newProgress {
//    NSLog(@"%f", newProgress);
//}

#pragma mark - POST 上传
- (void)postUpload {
    // url 是负责上传文件的脚本
    NSURL *url = [NSURL URLWithString:@"http://192.168.31.2/post/upload.php"];
    
    // 上传文件，同样可以在浏览器测试
    ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
    
    // 设置上传的文件
    /**
     参数
     1. 本地文件的路径
     2. 上传脚本中的字段名
     
     ASI会自动计算上传文件的 mime-Type
     */
    NSString *path = [[NSBundle mainBundle] pathForResource:@"demo.jpg" ofType:nil];
    //    [request addFile:path forKey:@"userfile"];
    /**
     参数
     1. 本地文件的路径
     2. 保存到服务器的文件名
     3. mime-Type
     4. 上传脚本中的字段名
     */
    [request addFile:path withFileName:@"aaa.jpg" andContentType:@"image/jpg" forKey:@"userfile"];
    
    // 发起网络连接
    // 设置完成块
    __weak typeof(request) weakSelf = request;
    [request setCompletionBlock:^{
        NSLog(@"%@", weakSelf.responseString);
    }];
    
    [request startAsynchronous];
}

/**
 为什么要 POST JSON -> RESTful风格的要求，用“浏览器”不能测试！
 
 －客户端最希望服务器返回JSON
 －可以用一句话反序列化－> 字典或者数组
 －字典转模型
 可以保证客户端代码的简洁，不容易出错
 
 －服务器为什么也希望要JSON
 －可以一句话反序列化！！！
 －客户端提交给服务器一个JSON，服务器就能够快速解析，并且做后续的处理！
 
 ASI不能自动做序列化&反序列化
 */
#pragma mark - POST JSON
- (void)postJSON {
    NSURL *url = [NSURL URLWithString:@"http://192.168.31.2/post/postjson.php"];
    
    // POST JSON 的请求还是 ASIHTTPRequest
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
    
    // 设置请求方法
    [request setRequestMethod:@"POST"];
    
    // 设置二进制数据
    NSDictionary *dict = @{@"productId": @(123), @"productName": @"da bao tian tain jian"};
    // 序列化，字典转JSON二进制数据
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
    
    [request setPostBody:[NSMutableData dataWithData:data]];
    
    // 设置完成块
    __weak typeof(request) weakSelf = request;
    [request setCompletionBlock:^{
        NSLog(@"%@", weakSelf.responseString);
    }];
    
    [request startAsynchronous];
}

#pragma mark - POST登录
- (void)postLogin {
    NSURL *url = [NSURL URLWithString:@"http://192.168.31.2/login.php"];
    
    // POST请求
    // 如果要使用 POST 请求，一般都使用 ASIFormDataRequest
    ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:url];
    
    // 设置httpBody
    [request setPostValue:@"zhangsan" forKey:@"username"];
    [request setPostValue:@"123" forKey:@"password"];
    
    __weak typeof(request) weakSelf = request;
    [request setCompletionBlock:^{
        NSLog(@"%@", weakSelf.responseString);
    }];
    
    [request startAsynchronous];
}

@end
