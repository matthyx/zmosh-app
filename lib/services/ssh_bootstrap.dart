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

    final cmd = 'PATH="\$PATH:/usr/local/bin:/opt/homebrew/bin:\$HOME/bin:\$HOME/.local/bin" zmosh serve "$sessionName"';
    final session = await client.execute(cmd);
    final completer = Completer<BootstrapResult>();
    final buffer = StringBuffer();

    void tryParseBuffer() {
      for (final line in buffer.toString().split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('ZMX_CONNECT ') || trimmed.startsWith('ZMOSH CONNECT ')) {
          final parts = trimmed.split(' ');
          int? udpPort;
          String? key;
          if (parts.length >= 4 && parts[1] == 'udp') {
            udpPort = int.tryParse(parts[2]);
            key = parts[3];
          } else if (parts.length >= 3) {
            udpPort = int.tryParse(parts[1]);
            key = parts[2];
          }
          if (udpPort != null && key != null && key.isNotEmpty && !completer.isCompleted) {
            completer.complete(BootstrapResult(udpPort: udpPort, keyBase64: key));
          }
        }
      }
    }

    final subscription = session.stdout.listen((Uint8List chunk) {
      final text = utf8.decode(chunk, allowMalformed: true);
      buffer.write(text);
      tryParseBuffer();
    }, onDone: () {
      tryParseBuffer();
    });

    final stderrBuffer = StringBuffer();
    session.stderr.listen((Uint8List chunk) {
      final text = utf8.decode(chunk, allowMalformed: true);
      stderrBuffer.write(text);
      print('[zmosh serve stderr]: $text');
    });

    session.done.then((_) async {
      await Future.delayed(const Duration(milliseconds: 300));
      tryParseBuffer();
      if (!completer.isCompleted) {
        final err = stderrBuffer.toString().trim();
        if (err.contains('command not found') || err.contains('not found')) {
          completer.completeError(
            Exception(
              'zmosh is not installed or not in PATH on the remote host.\n\n'
              'Please install zmosh on the server:\n'
              'https://github.com/matthyx/zmosh/releases',
            ),
          );
        } else if (err.contains('UnknownCommand') || err.contains('unrecognized') || err.contains('Usage:')) {
          completer.completeError(
            Exception(
              'The zmosh binary on the remote host does not support "serve".\n\n'
              'Please upgrade zmosh to v1.1.0+ on the server:\n'
              'https://github.com/matthyx/zmosh/releases',
            ),
          );
        } else if (err.isNotEmpty) {
          completer.completeError(
            Exception('Remote zmosh failed with error:\n$err'),
          );
        } else {
          completer.completeError(
            Exception(
              'Remote process closed without outputting connection info.\n'
              'Ensure zmosh (>= 1.0.0) is installed on the host.',
            ),
          );
        }
      }
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
