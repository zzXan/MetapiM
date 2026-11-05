import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:home_widget/home_widget.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'src/metapi_client.dart';
import 'src/server_address.dart';

void main() => runApp(const MetapiMApp());

class MetapiMApp extends StatelessWidget {
  const MetapiMApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MetapiM', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xff359792), useMaterial3: true),
    darkTheme: ThemeData(colorSchemeSeed: const Color(0xff359792), brightness: Brightness.dark, useMaterial3: true),
    home: const ConnectionScreen(),
  );
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});
  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  static const storage = FlutterSecureStorage();
  final address = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool restoring = true;
  String? error;
  @override
  void initState() { super.initState(); unawaited(restore()); }
  Future<void> restore() async {
    try {
      final raw = await storage.read(key: 'metapim.session');
      if (raw != null && mounted) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        address.text = data['server'] as String;
        password.text = data['token'] as String;
        final server = ServerAddress.parse(address.text);
        final token = password.text;
        if (mounted) {
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ServerScreen(server: server, token: token)));
          password.clear();
        }
      }
    } catch (_) { error = '无法读取已保存连接，请重新登录'; }
    if (mounted) setState(() => restoring = false);
  }
  Future<void> connect() async {
    setState(() { busy = true; error = null; });
    MetapiClient? client;
    try {
      final server = ServerAddress.parse(address.text);
      final token = password.text.trim();
      if (token.isEmpty) throw const FormatException('请输入管理员 Token');
      client = MetapiClient(server: server, token: token);
      await client.validate().timeout(const Duration(seconds: 30));
      await storage.write(key: 'metapim.session', value: jsonEncode({'server': server.toString(), 'token': token}));
      if (!mounted) return;
      password.clear();
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ServerScreen(server: server, token: token)));
    } catch (e) {
      if (mounted) setState(() => error = e is TimeoutException ? '连接超时，请检查服务器地址和网络' : e.toString());
    } finally { client?.close(); if (mounted) setState(() => busy = false); }
  }
  @override
  void dispose() { address.dispose(); password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('连接 MetapiM')),
    body: SafeArea(child: restoring ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(24), children: [
      const Text('连接你的 Metapi 服务器', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12), const Text('网页功能与界面直接来自服务器；连接凭据保存在 iOS Keychain。'),
      const SizedBox(height: 24),
      TextField(controller: address, keyboardType: TextInputType.url, autocorrect: false, textCapitalization: TextCapitalization.none, decoration: const InputDecoration(labelText: '服务器地址', hintText: 'https://metapi.example.com', border: OutlineInputBorder())),
      const SizedBox(height: 16),
      TextField(controller: password, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: '管理员密码 / Token', border: OutlineInputBorder()), onSubmitted: (_) { if (!busy) unawaited(connect()); }),
      const SizedBox(height: 12), if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 12), FilledButton(onPressed: busy ? null : connect, child: Text(busy ? '连接中…' : '连接')),
    ])),
  );
}

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.server, required this.token});
  final ServerAddress server;
  final String token;
  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> with WidgetsBindingObserver {
  late final WebViewController controller;
  bool loading = true;
  bool refreshing = false;
  bool loggingOut = false;
  String? error;
  DateTime lastForeground = DateTime.fromMillisecondsSinceEpoch(0);
  bool sessionInjected = false;
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final target = Uri.tryParse(request.url);
          return target != null && widget.server.contains(target) ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
        onPageStarted: (_) { if (mounted) setState(() { loading = true; error = null; }); },
        onPageFinished: (url) async {
          final target = Uri.tryParse(url);
          if (!sessionInjected && target != null && widget.server.contains(target)) {
            sessionInjected = true;
            final token = jsonEncode(widget.token);
            final expiry = DateTime.now().add(const Duration(hours: 12)).millisecondsSinceEpoch;
            await controller.runJavaScript('''
              (() => {
                const token = $token;
                if (localStorage.getItem('auth_token') !== token ||
                    Number(localStorage.getItem('auth_token_expires_at') || 0) <= Date.now()) {
                  localStorage.setItem('auth_token', token);
                  localStorage.setItem('auth_token_expires_at', '$expiry');
                  location.reload();
                }
              })();
            ''');
          }
          if (mounted) setState(() => loading = false);
        },
        onWebResourceError: (e) { if (mounted && e.isForMainFrame == true) setState(() { error = '网页加载失败，请检查网络后重试'; loading = false; }); },
      ));
    unawaited(open());
    unawaited(refreshWidget());
  }
  Future<void> open() async {
    // Load only the configured origin. Once its page finishes, the guarded
    // bootstrap above installs the existing web session and reloads once.
    try {
      await controller.loadRequest(widget.server.uri, headers: {'Authorization': 'Bearer ${widget.token}', 'Cache-Control': 'no-cache'});
    } catch (_) { if (mounted) setState(() { error = '无法打开网页'; loading = false; }); }
  }
  Future<void> configureSharedGroup() async {
    final group = await const MethodChannel('metapim/shared-group').invokeMethod<String>('resolve');
    if (group == null || group.isEmpty) throw StateError('签名缺少共享容器');
    await HomeWidget.setAppGroupId(group);
  }
  Future<void> refreshWidget() async {
    if (refreshing || loggingOut) return;
    refreshing = true;
    final client = MetapiClient(server: widget.server, token: widget.token);
    try {
      await configureSharedGroup();
      await const MethodChannel('metapim/shared-group').invokeMethod<void>('saveSession', {
        'server': widget.server.toString(), 'token': widget.token,
      });
      final snapshot = await client.loadWidgetSnapshot().timeout(const Duration(seconds: 30));
      if (loggingOut || !mounted) return;
      final encoded = snapshot.encode();
      await HomeWidget.saveWidgetData<String>('metapim.snapshot', encoded);
      final stored = await HomeWidget.getWidgetData<String>('metapim.snapshot');
      if (stored != encoded) throw StateError('共享缓存写入后校验失败');
      await HomeWidget.updateWidget(iOSName: 'MetapiMWidget');
    } catch (e) {
      // Preserve the last successful snapshot and expose a safe error category.
      final reason = e is MetapiAuthException ? '认证失败'
          : e is FormatException ? '接口数据格式不兼容'
          : e is TimeoutException ? '请求超时'
          : e is HttpException ? e.message
          : '网络或 App Group 共享缓存不可用（SideStore 重签后请检查共享权限）';
      if (mounted) setState(() => error = 'Widget 刷新失败：$reason');
    } finally { client.close(); refreshing = false; }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && DateTime.now().difference(lastForeground).inSeconds >= 15) {
      lastForeground = DateTime.now(); unawaited(controller.reload()); unawaited(refreshWidget());
    }
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: Theme.of(context).colorScheme.surface,
      child: PopupMenuButton<String>(
        tooltip: '操作',
        icon: const Icon(Icons.settings_outlined, size: 22),
        onSelected: (action) async {
          if (action == 'refresh') {
            unawaited(controller.reload());
            unawaited(refreshWidget());
            return;
          }
          if (action != 'logout') return;
          loggingOut = true;
          while (refreshing) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          try {
          await const MethodChannel('metapim/shared-group').invokeMethod<void>('clearSession');
          await _ConnectionScreenState.storage.delete(key: 'metapim.session');
          await controller.clearLocalStorage();
          await controller.clearCache();
          await configureSharedGroup();
          await HomeWidget.saveWidgetData<String>('metapim.snapshot', null);
          await HomeWidget.updateWidget(iOSName: 'MetapiMWidget');
          if (context.mounted) Navigator.of(context).pop();
          } catch (_) {
            loggingOut = false;
            if (mounted) setState(() => error = '登出未完成：无法清除共享凭据，请检查共享权限后重试');
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'refresh', child: Text('刷新')),
          PopupMenuItem(value: 'logout', child: Text('登出')),
        ],
      ),
    ),
    body: SafeArea(child: Column(children: [
      if (loading) const LinearProgressIndicator(),
      if (error != null) MaterialBanner(content: Text(error!), actions: [TextButton(onPressed: open, child: const Text('重试'))]),
      Expanded(child: WebViewWidget(controller: controller)),
    ])),
  );
}