// Compile to build/test_support/llama-server.exe for the process lifecycle test.
// This fixture never loads a model and only serves a loopback health check.
import 'dart:io';

Future<void> main(List<String> args) async {
  final port = int.parse(args[args.indexOf('--port') + 1]);
  final key = args[args.indexOf('--api-key') + 1];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  await for (final request in server) {
    request.response.statusCode =
        request.headers.value('authorization') == 'Bearer $key' ? 200 : 401;
    request.response.write('{}');
    await request.response.close();
  }
}
