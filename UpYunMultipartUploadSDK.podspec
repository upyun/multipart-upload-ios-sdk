Pod::Spec.new do |spec|
  spec.name         = 'UpYunMultipartUploadSDK'
  spec.version      = '0.0.1'
  spec.summary      = 'UpYunMultipartUploadSDK'
  spec.source_files = 'UpYunMultipartUploadSDK/Classes/*.{h,m}'
  spec.requires_arc = true
  spec.ios.deployment_target = '6.0'
  spec.dependency 'AFNetworking', '~> 2.2.4'
end
