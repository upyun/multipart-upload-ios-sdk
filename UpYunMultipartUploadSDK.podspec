Pod::Spec.new do |spec|
  spec.name         = 'UpYunMultipartUploadSDK'
  spec.version      = '0.0.2'
  spec.summary      = 'UpYunMultipartUploadSDK'
  spec.source_files = 'UpYunMultipartUploadSDK/Classes/*.{h,m}'
  spec.requires_arc = true
  spec.ios.deployment_target = '7.0'
  spec.dependency 'AFNetworking'
end
