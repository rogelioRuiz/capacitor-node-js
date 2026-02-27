require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'CapacitorNodejs'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = package['repository']['url']
  s.author = package['author']
  s.source = { :git => package['repository']['url'], :tag => s.version.to_s }
  s.source_files = 'ios/Bridge/**/*.{h,m,c,cc,mm,cpp}', 'ios/Swift/**/*.swift'
  s.ios.deployment_target = '13.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.1'

  # NodeMobile framework (Node.js v18.20.4, V8 JIT-less for App Store)
  s.vendored_frameworks = 'ios/libnode/NodeMobile.xcframework'
  s.frameworks = 'Foundation'

  # C++ build settings for bridge.cpp compilation
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/ios/libnode/include/node/"',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'DEFINES_MODULE' => 'YES',
    'ENABLE_BITCODE' => 'NO'
  }

  # Ensure bitcode is disabled project-wide (NodeMobile doesn't support it)
  s.user_target_xcconfig = {
    'ENABLE_BITCODE' => 'NO'
  }

  # Bundle the bridge JS module for Node.js
  s.resources = ['ios/assets/builtin_modules/**/*']
end
