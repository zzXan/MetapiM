import Flutter

final class SharedGroupPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "metapim/shared-group", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(SharedGroupPlugin(), channel: channel)
    }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let group = SharedGroup.resolve() else {
            result(FlutterError(code: "APP_GROUP_UNAVAILABLE", message: "签名未提供可访问的 MetapiM App Group", details: nil)); return
        }
        do {
            switch call.method {
            case "resolve": result(group)
            case "saveSession":
                guard let args = call.arguments as? [String: String],
                      let server = args["server"], let token = args["token"] else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "缺少连接信息", details: nil)); return
                }
                try WidgetSession(server: server, token: token).save(group: group)
                result(nil)
            case "clearSession": try WidgetSession.clear(group: group); result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        } catch {
            result(FlutterError(code: "SHARED_KEYCHAIN_UNAVAILABLE", message: "共享 Keychain 不可用，请检查重签权限", details: nil))
        }
    }
}
