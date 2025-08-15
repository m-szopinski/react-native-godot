Pod::Spec.new do |s|
  s.name         = "RNGodot"
  s.version      = "0.4.5"  # pozostaw lub podbij jeśli publikujesz
  s.summary      = "Godot bridge for React Native"
  s.homepage     = "https://github.com/m-szopinski/react-native-godot"
  s.license      = { :type => "MIT" }
  s.author       = { "m-szopinski" => "szopinski.michal@gmail.com" }
  s.platforms    = { :ios => "13.0", :osx => "11.0" }
  s.source       = { :git => "https://github.com/m-szopinski/react-native-godot.git", :tag => s.version.to_s }
  s.source_files = "ios/**/*.{h,m,mm,swift}"
  s.swift_version = "5.9"
  s.requires_arc = true
  s.preserve_paths = "build-godot.sh", "GodotBuild/**/*"
  s.vendored_frameworks = 'GodotBuild/Godot.xcframework'
  s.static_framework = true  # Godot linkowany statycznie – łatwiejsze dystrybuowanie
  s.prepare_command = <<-CMD
    echo "[RNGodot] prepare start"
    bash #{File.dirname(__FILE__)}/build-godot.sh || echo "[RNGodot] build-godot.sh ostrzeżenie"
    if [ -d "GodotBuild/Godot.xcframework" ]; then
      echo "[RNGodot] Godot.xcframework OK"
      echo "[RNGodot] Dodaj wrapper (rn_godot_*), zarejestruj engine lub użyj registerCallbacks()."
    else
      echo "[RNGodot][WARN] Brak Godot.xcframework – zostanie użyty stub."
    fi
    echo "[RNGodot] prepare end"
  CMD
  s.resource_bundles = {
    'RNGodotProject' => ['godot-project/**/*']
  }
  s.dependency "React-Core"
  s.frameworks = []  # brak SceneKit – realny render zapewnia silnik Godot
end
