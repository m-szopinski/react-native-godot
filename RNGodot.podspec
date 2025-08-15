require 'json'
package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = "RNGodot"
  s.version      = package['version']
  s.summary      = package['description']
  s.license      = package['license']
  s.authors      = package['author']
  s.homepage     = package['repository']['url']
  s.source       = { :git => package['repository']['url'], :tag => "#{s.version}" }

  s.platforms    = { :ios => "13.0", :osx => "11.0" }

  # Tu definiujemy źródła — brak xcodeproj, więc CocoaPods sam kompiluje
  s.source_files = "ios/**/*.{h,m,mm,swift}"

  # Dołączamy Godot.framework
  s.vendored_frameworks = "ios/Godot.framework"

  s.dependency "React-Core"
  s.swift_version = "5.0"

  s.pod_target_xcconfig = {
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) $(PODS_ROOT)/Godot'
  }
end
