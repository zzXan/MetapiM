require 'xcodeproj'
require 'fileutils'
require 'rexml/document'

root = File.expand_path('..', __dir__)
ios = File.join(root, 'ios')
project = Xcodeproj::Project.open(File.join(ios, 'Runner.xcodeproj'))
app = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target missing' unless app
widget = project.targets.find { |t| t.name == 'MetapiMWidget' } || project.new_target(:app_extension, 'MetapiMWidget', :ios, '17.0')
group = project.main_group.find_subpath('MetapiMWidget', true)
group.set_source_tree('<group>')
FileUtils.mkdir_p(File.join(ios, 'MetapiMWidget'))
FileUtils.cp(File.join(root, 'ios-support', 'MetapiMWidget.swift'), File.join(ios, 'MetapiMWidget', 'MetapiMWidget.swift'))
ref = group.files.find { |f| f.path == 'MetapiMWidget/MetapiMWidget.swift' } || group.new_file('MetapiMWidget/MetapiMWidget.swift')
widget.add_file_references([ref]) unless widget.source_build_phase.files_references.include?(ref)
app.add_dependency(widget) unless app.dependencies.any? { |d| d.target == widget }
phase = app.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' } || app.new_copy_files_build_phase('Embed App Extensions')
phase.dst_subfolder_spec = '13'
phase.add_file_reference(widget.product_reference) unless phase.files_references.include?(widget.product_reference)
# Flutter's generated Thin Binary script can create a dependency from its
# signing/thinning work back to Runner.app/Info.plist. A copy phase appended
# after Thin Binary forms a cycle through that app bundle. Embed the extension
# before Flutter's Thin Binary phase.
if (thin_binary = app.shell_script_build_phases.find { |p| p.name == 'Thin Binary' })
 phases = app.build_phases
 phases.delete(phase)
 phases.insert(phases.index(thin_binary), phase)
end

entitlements = { 'com.apple.security.application-groups' => ['group.com.zzxan.metapim'] }
Xcodeproj::Plist.write_to_path(entitlements, File.join(ios, 'Runner', 'Runner.entitlements'))
Xcodeproj::Plist.write_to_path(entitlements, File.join(ios, 'MetapiMWidget', 'Widget.entitlements'))
Xcodeproj::Plist.write_to_path({
 'CFBundleName' => 'MetapiMWidget',
 'CFBundleDisplayName' => 'MetapiM', 'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)',
 'CFBundleExecutable' => '$(EXECUTABLE_NAME)', 'CFBundlePackageType' => 'XPC!',
 'CFBundleVersion' => '1', 'CFBundleShortVersionString' => '0.0.1',
 'NSExtension' => { 'NSExtensionPointIdentifier' => 'com.apple.widgetkit-extension' }
}, File.join(ios, 'MetapiMWidget', 'Info.plist'))
app.build_configurations.each do |c|
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.zzxan.metapim'
 c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
 c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end
widget.add_build_configuration('Profile', :release) unless widget.build_configurations.any? { |c| c.name == 'Profile' }
widget.build_configurations.each do |c|
 # Newly generated extension configurations must not inherit an empty name.
 c.build_settings['PRODUCT_NAME'] = 'MetapiMWidget'
 c.build_settings['PRODUCT_MODULE_NAME'] = 'MetapiMWidget'
 c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.zzxan.metapim.widget'
 c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
 c.build_settings['SWIFT_VERSION'] = '5.0'
 c.build_settings['INFOPLIST_FILE'] = 'MetapiMWidget/Info.plist'
 c.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
 c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'MetapiMWidget/Widget.entitlements'
 c.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
 c.build_settings['SKIP_INSTALL'] = 'YES'
 c.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
end
info = File.join(ios, 'Runner', 'Info.plist')
plist = Xcodeproj::Plist.read_from_path(info)
plist['CFBundleDisplayName'] = 'MetapiM'
plist['CFBundleName'] = 'MetapiM'
plist['NSLocalNetworkUsageDescription'] = '连接你配置的局域网 Metapi 服务器。'
plist['NSAppTransportSecurity'] = { 'NSAllowsArbitraryLoads' => true }
Xcodeproj::Plist.write_to_path(plist, info)
project.save
# Validate serialized configurations, including Profile, before invoking Xcode.
verified = Xcodeproj::Project.open(File.join(ios, 'Runner.xcodeproj'))
verified.targets.select { |t| t.name == 'MetapiMWidget' }.each do |target|
 target.build_configurations.each do |config|
  raise "Empty widget product in #{config.name}" unless config.build_settings['PRODUCT_NAME'] == 'MetapiMWidget'
 end
end
runner_phases = verified.targets.find { |t| t.name == 'Runner' }.build_phases
embed = runner_phases.find { |p| p.respond_to?(:name) && p.name == 'Embed App Extensions' }
thin = runner_phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if embed && thin && runner_phases.index(embed) >= runner_phases.index(thin)
 raise 'Embed App Extensions must precede Thin Binary'
end
podfile = File.join(ios, 'Podfile')
if File.exist?(podfile)
 text = File.read(podfile)
 text.sub!(/^#?\s*platform :ios,.*$/, "platform :ios, '17.0'")
 File.write(podfile, text)
end
puts 'Configured MetapiM Runner and WidgetKit extension'
