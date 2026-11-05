import Flutter

final class SharedGroupPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "metapim/shared-group", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(SharedGroupPlugin(), channel: channel)
    }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "resolve" else { result(FlutterMethodNotImplemented); return }
        if let group = SharedGroup.resolve() { result(group) }
        else { result(FlutterError(code: "APP_GROUP_UNAVAILABLE", message: "签名未提供可访问的 MetapiM App Group", details: nil)) }
    }
}
