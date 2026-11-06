import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

class BootstrapResult {
  final int udpPort;
  final String keyBase64;

  BootstrapResult({
    required this.udpPort,
    required this.keyBase64,
  });
}

class SshBootstrap {
  /// Connects to remote SSH host, executes `zmosh serve <session>`,
  /// parses the `ZMOSH CONNECT <port> <key>` line, and returns the parameters.
  static Future<BootstrapResult> bootstrap({
    required String host,
    int port = 22,
    required String username,
    String? password,
    String? privateKey,
    required String sessionName,
  }) async {
    final socket = await SSHSocket.connect(host, port);
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () {
        if (password != null) return password;
        throw StateError('Password authentication required but no password provided');
      },
      identities: privateKey != null
          ? SSHKeyPair.fromPem(privateKey)
          : null,
    );

    await client.authenticated;

    final session = await client.execute('zmosh serve "$sessionName"');
    final completer = Completer<BootstrapResult>();
    final buffer = StringBuffer();

    final subscription = session.stdout.listen((Uint8List chunk) {
      final text = utf8.decode(chunk, allowMalformed: true);
      buffer.write(text);

      for (final line in buffer.toString().split('\n')) {
        final trimmed = line.trim();
        // Look for: ZMOSH CONNECT <port> <base64_key>
        if (trimmed.startsWith('ZMOSH CONNECT ')) {
          final parts = trimmed.split(' ');
          if (parts.length >= 4) {
            final udpPort = int.tryParse(parts[2]);
            final key = parts[3];
            if (udpPort != null && key.isNotEmpty && !completer.isCompleted) {
              completer.complete(BootstrapResult(udpPort: udpPort, keyBase64: key));
            }
          }
        }
      }
    });

    session.stderr.listen((Uint8List chunk) {
      final text = utf8.decode(chunk, allowMalformed: true);
      // Log or handle stderr
      print('[zmosh serve stderr]: $text');
    });

    try {
      final result = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Timed out waiting for zmosh serve handshake');
        },
      );
      return result;
    } finally {
      // Do not kill the remote session: zmosh serve runs as a background gateway daemon!
      // Close SSH connection gracefully
      unawaited(subscription.cancel());
      client.close();
    }
  }
}
