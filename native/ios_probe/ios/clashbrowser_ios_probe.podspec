Pod::Spec.new do |s|
  s.name = 'clashbrowser_ios_probe'
  s.version = '0.0.1'
  s.summary = 'Internal native core version bridge.'
  s.description = 'Links the pinned Clash iOS SDK for a read-only version probe.'
  s.homepage = 'https://github.com/NoRegret-L/ClashBrowser'
  s.license = { :type => 'GPL-3.0', :file => 'Frameworks/LICENSE' }
  s.author = { 'ClashBrowser contributors' => 'noreply@example.invalid' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '17.0'
  # Upstream static SDK requires the Apple DNS resolver library.
  s.libraries = 'resolv'
  s.frameworks = 'WebKit', 'Network'
  s.static_framework = true
  s.vendored_frameworks = 'Frameworks/Clash.xcframework'
end
