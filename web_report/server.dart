import 'dart:convert';
import 'dart:io';

/// 默认监听端口。报表数据存于浏览器 IndexedDB（按 origin 隔离），
/// 因此优先固定端口，保证多次启动后仍能读到上次导入的数据。
const int _defaultPort = 8765;

/// 端口被占用时最多向后尝试的次数。
const int _portProbeRange = 20;

/// 报表服务入口：启动本地静态服务器并自动打开浏览器。
///
/// 参数：[args] 支持 `--port=8765` 指定端口、`--no-browser` 仅启动不打开浏览器。
Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final webDir = _resolveWebDir();
  final indexFile = File(_join(webDir.path, 'index.html'));
  if (!indexFile.existsSync()) {
    stderr.writeln('未找到前端文件：${indexFile.path}');
    stderr.writeln('请确认 web 目录与程序位于同一目录，或从项目根目录运行。');
    exitCode = 2;
    return;
  }

  final existing = await _findRunningInstance(options.port ?? _defaultPort);
  if (existing != null) {
    final url = 'http://127.0.0.1:$existing/';
    stdout.writeln('报表服务已在运行：$url');
    if (options.openBrowser) _openBrowser(url);
    return;
  }

  final server = await _bindServer(webDir, options.port ?? _defaultPort);
  final url = 'http://127.0.0.1:${server.port}/';
  server.listen((request) => _handleRequest(request, webDir));
  stdout.writeln('包裹管家报表已启动：$url');
  stdout.writeln('数据只保存在本机浏览器，关闭窗口后可再次打开同一地址查看。');
  stdout.writeln('按 Ctrl+C 可停止服务。');
  if (options.openBrowser) _openBrowser(url);
}

/// 命令行参数。
class _Options {
  const _Options({this.port, this.openBrowser = true});

  /// 指定端口，为空时使用默认端口。
  final int? port;

  /// 启动后是否自动打开浏览器。
  final bool openBrowser;
}

/// 解析命令行参数。
///
/// 参数：[args] 原始参数列表。
/// 返回：解析后的选项，无法识别的参数会被忽略。
_Options _parseArgs(List<String> args) {
  int? port;
  var openBrowser = true;
  for (final arg in args) {
    if (arg.startsWith('--port=')) {
      port = int.tryParse(arg.substring('--port='.length));
    } else if (arg == '--no-browser') {
      openBrowser = false;
    }
  }
  return _Options(port: port, openBrowser: openBrowser);
}

/// 定位前端静态资源目录。
///
/// 返回：优先使用可执行文件同级的 `web`（打包后），
/// 其次使用脚本同级的 `web`（源码运行），最后回退到当前目录的 `web`。
Directory _resolveWebDir() {
  final executableDir = File(Platform.resolvedExecutable).parent.path;
  final scriptDir = File.fromUri(Platform.script).parent.path;
  final candidates = <String>[
    _join(executableDir, 'web'),
    _join(scriptDir, 'web'),
    _join(Directory.current.path, 'web'),
    _join(_join(Directory.current.path, 'web_report'), 'web'),
  ];
  for (final candidate in candidates) {
    if (File(_join(candidate, 'index.html')).existsSync()) {
      return Directory(candidate);
    }
  }
  return Directory(candidates.first);
}

/// 探测目标端口上是否已经跑着本报表服务。
///
/// 参数：[port] 期望端口。
/// 返回：已运行服务的端口；未运行时返回 null。
Future<int?> _findRunningInstance(int port) async {
  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 600);
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/api/health'),
    );
    final response = await request.close().timeout(
      const Duration(milliseconds: 900),
    );
    final body = await response.transform(utf8.decoder).join();
    client.close(force: true);
    if (response.statusCode == 200 && body.contains('packkeeper-report')) {
      return port;
    }
  } catch (_) {
    // 端口空闲或不是本服务，继续走正常启动流程。
  }
  return null;
}

/// 绑定 HTTP 监听端口，被占用时向后顺延。
///
/// 参数：[webDir] 前端目录；[startPort] 起始端口。
/// 返回：已绑定成功的服务器。
Future<HttpServer> _bindServer(Directory webDir, int startPort) async {
  Object? lastError;
  for (var offset = 0; offset < _portProbeRange; offset++) {
    final port = startPort + offset;
    try {
      return await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException catch (error) {
      lastError = error;
    }
  }
  stderr.writeln('端口 $startPort 起连续 $_portProbeRange 个端口均被占用。');
  throw StateError('无法绑定本地端口：$lastError');
}

/// 处理单个 HTTP 请求：健康检查与静态文件。
///
/// 参数：[request] 客户端请求；[webDir] 前端目录。
Future<void> _handleRequest(HttpRequest request, Directory webDir) async {
  final response = request.response;
  try {
    if (request.uri.path == '/api/health') {
      response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'app': 'packkeeper-report'}));
      await response.close();
      return;
    }

    var relative = Uri.decodeComponent(request.uri.path);
    if (relative == '/' || relative.isEmpty) relative = '/index.html';
    final file = File(_join(webDir.path, relative.replaceAll('/', Platform.pathSeparator)));
    if (!_isInside(webDir.path, file.path) || !file.existsSync()) {
      response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.html
        ..write('<meta charset="utf-8"><p>页面不存在</p>');
      await response.close();
      return;
    }

    response.headers
      ..contentType = _contentType(file.path)
      ..set('Cache-Control', 'no-store');
    await response.addStream(file.openRead());
    await response.close();
  } catch (error) {
    response
      ..statusCode = HttpStatus.internalServerError
      ..write('服务器错误：$error');
    await response.close();
  }
}

/// 校验目标文件是否位于资源目录内，避免路径穿越。
///
/// 参数：[root] 资源根目录绝对路径；[target] 目标文件绝对路径。
/// 返回：目标在根目录内返回 true。
bool _isInside(String root, String target) {
  final normalizedRoot = Directory(root).absolute.path.toLowerCase();
  final normalizedTarget = File(target).absolute.path.toLowerCase();
  return normalizedTarget == normalizedRoot ||
      normalizedTarget.startsWith('$normalizedRoot${Platform.pathSeparator}');
}

/// 根据扩展名返回 Content-Type。
///
/// 参数：[path] 文件路径。
/// 返回：对应的 MIME 类型，未知类型按二进制流返回。
ContentType _contentType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.html')) return ContentType.html;
  if (lower.endsWith('.css')) return ContentType('text', 'css', charset: 'utf-8');
  if (lower.endsWith('.js')) return ContentType('text', 'javascript', charset: 'utf-8');
  if (lower.endsWith('.json')) return ContentType.json;
  if (lower.endsWith('.svg')) return ContentType('image', 'svg+xml');
  if (lower.endsWith('.png')) return ContentType('image', 'png');
  if (lower.endsWith('.ico')) return ContentType('image', 'x-icon');
  return ContentType.binary;
}

/// 拼接路径片段。
///
/// 参数：[base] 基础路径；[child] 子路径。
/// 返回：使用当前平台分隔符拼接后的路径。
String _join(String base, String child) {
  final separator = Platform.pathSeparator;
  if (base.endsWith(separator)) {
    return child.startsWith(separator) ? '$base${child.substring(1)}' : '$base$child';
  }
  return child.startsWith(separator) ? '$base$child' : '$base$separator$child';
}

/// 用系统默认浏览器打开指定地址。
///
/// 参数：[url] 本地服务地址。
void _openBrowser(String url) {
  try {
    if (Platform.isWindows) {
      Process.start('cmd', ['/c', 'start', '', url], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      Process.start('open', [url], mode: ProcessStartMode.detached);
    } else {
      Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
    }
  } catch (error) {
    stdout.writeln('自动打开浏览器失败，请手动访问：$url（$error）');
  }
}
