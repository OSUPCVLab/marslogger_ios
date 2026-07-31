require "xcodeproj"

project_path = File.expand_path("../MarsLogger.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |target| target.name == "MarsLoggerOpenGL" }
test_target = project.targets.find { |target| target.name == "MarsLoggerTests" }
raise "MarsLoggerOpenGL target not found" unless app_target

group = project.main_group.find_subpath("ModernSwift", true)
group.set_source_tree("<group>")

app_source_names = %w[
  MarsLoggerApp.swift
  LoggerView.swift
  CaptureController.swift
  CaptureWriter.swift
]

app_target.source_build_phase.files.to_a.each(&:remove_from_project)
app_source_names.each do |name|
  reference = group.files.find { |file| file.path == name } || group.new_file(name)
  app_target.source_build_phase.add_file_reference(reference, true)
end

if test_target
  test_reference = group.files.find { |file| file.path == "CaptureSchemaTests.swift" } || group.new_file("CaptureSchemaTests.swift")
  test_target.source_build_phase.add_file_reference(test_reference, true)
end

%w[ARKit SceneKit].each do |framework|
  app_target.add_system_framework(framework)
end

app_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["IPHONEOS_DEPLOYMENT_TARGET"] = "15.0"
  settings["SWIFT_VERSION"] = "5.0"
  settings["SWIFT_STRICT_CONCURRENCY"] = "targeted"
  settings["GCC_PRECOMPILE_PREFIX_HEADER"] = "NO"
  settings.delete("GCC_PREFIX_HEADER")
  settings.delete("DEVELOPMENT_TEAM")
end

if test_target
  test_target.build_configurations.each do |configuration|
    configuration.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "15.0"
    configuration.build_settings["SWIFT_VERSION"] = "5.0"
  end
end

project.save
