#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint yucheng_ble.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'yucheng_ble'
  s.version          = '0.0.1'
  s.summary          = 'Plugin for yucheng'
  s.description      = <<-DESC
Plugin for yucheng
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.preserve_paths = 'YCProductSDK.framework', 'ZipZap.framework', 'RTKOTASDK.framework', 'RTKLEFoundation.framework', 'JLDialUnit.framework', 'JL_OTALib.framework', 'JL_HashPair.framework', 'JL_BLEKit.framework', 'JL_AdvParse.framework', 'DFUnits.framework'
  s.xcconfig = { 'OTHER_LDFLAGS' => '-framework YCProductSDK -framework ZipZap -framework RTKOTASDK -framework RTKLEFoundation -framework JLDialUnit -framework JL_OTALib -framework JL_HashPair -framework JL_BLEKit -framework JL_AdvParse -framework DFUnits' }
  s.vendored_frameworks = 'YCProductSDK.framework', 'ZipZap.framework', 'RTKOTASDK.framework', 'RTKLEFoundation.framework', 'JLDialUnit.framework', 'JL_OTALib.framework', 'JL_HashPair.framework', 'JL_BLEKit.framework', 'JL_AdvParse.framework', 'DFUnits.framework'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES'}
  s.swift_version = '5.0'
end
