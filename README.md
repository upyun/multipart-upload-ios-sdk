# 又拍云iOS 分块上传 SDK

又拍云存储iOS 分块上传 SDK，基于 [又拍云存储 分块上传 API接口] (http://docs.upyun.com/api/multipart_upload/) 开发。
## 使用说明
### 要求
iOS6.0及以上版本，ARC模式，AFNetworking 1.3.4及以上

### 问题说明
下载之后如果发现没有pod项目,可以进入到项目目录使用```` pod install ````解决

如果install时间过长，可以使用 ````pod install --verbose --no-repo-update ````
### 初始化UpYun
````
UMUUploaderManager * manager = [UMUUploaderManager managerWithBucket:<bucket>];
````

### 上传文件
````
[manager uploadWithFile:<fileData> 
                 policy:<policy> 
              signature:<signature> 
          progressBlock:<progressBlock> 
          completeBlock:<completeBlock>];
````
##### 参数说明：

#####1、`fileData` 需要上传的文件数据
* 可传入类型：
 * `NSData`
 
#####2、`policy` 存储/校验信息（生成方式详细见Demo或者 [分块上传 API接口 signature和policy算法] (http://docs.upyun.com/api/multipart_upload/#_1) ）
* 可传入类型：
 * `NSString`
 
#####3、`signature` 校验签名（生成方式详细见Demo或者 [分块上传 API接口 signature和policy算法] (http://docs.upyun.com/api/multipart_upload/#_1) ）
* 可传入类型：
 * `NSString`

#####4、`progressBlock` 上传进度度回调
* 回调中的参数：
 * `percent`: 上传进度的百分比
 * `requestDidSendBytes`: 已经发送的数据量
 
#####5、`completeBlock` 上传完成回调
* 回调中的参数：
 * `completed`: 是否成功
 * `result`: 成功后服务端返回的数据
 * `error`: 失败时的错误信息

### 错误代码
* 误代码详见 [分块上传 API 错误代码表](http://docs.upyun.com/api/multipart_upload/#_18) 
