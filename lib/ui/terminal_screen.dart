import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../ffi/zmosh_bindings.dart';

class TerminalScreen extends StatefulWidget {
  final ZmoshSession session;
  final String sessionTitle;

  const TerminalScreen({
    super.key,
    required this.session,
    required this.sessionTitle,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  ZmoshState _state = ZmoshState.connected;
  bool _ctrlActive = false;
  bool _altActive = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 5000);
    _terminalController = TerminalController();

    // Route user input from xterm to native zmosh UDP link
    _terminal.onOutput = (String data) {
      if (_ctrlActive || _altActive) {
        // Special modifier handling
        _sendWithModifiers(data);
      } else {
        widget.session.sendString(data);
      }
    };

    // Route terminal resize to remote zmx session
    _terminal.onResize = (int width, int height, int pixelWidth, int pixelHeight) {
      widget.session.resize(height, width);
    };

    // Forward received UDP output directly into the xterm emulator
    widget.session.onOutput = (List<int> bytes) {
      final text = utf8.decode(bytes, allowMalformed: true);
      _terminal.write(text);
    };

    // Listen to network state changes
    widget.session.onStateChanged = (ZmoshState state) {
      if (mounted) {
        setState(() {
          _state = state;
        });
      }
    };

    // Handle session end
    widget.session.onSessionEnded = () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Remote session has ended')),
        );
        Navigator.of(context).pop();
      }
    };
  }

  void _sendWithModifiers(String input) {
    if (input.isEmpty) return;
    final code = input.codeUnitAt(0);

    if (_ctrlActive) {
      // Convert ASCII character to control code (A -> 1, Z -> 26, etc.)
      int ctrlCode = code;
      if (code >= 65 && code <= 90) {
        ctrlCode = code - 64;
      } else if (code >= 97 && code <= 122) {
        ctrlCode = code - 96;
      }
      widget.session.sendInput([ctrlCode]);
      setState(() => _ctrlActive = false);
    } else if (_altActive) {
      // ESC prefix for Alt
      widget.session.sendInput([27, code]);
      setState(() => _altActive = false);
    }
  }

  void _sendKey(String sequence) {
    widget.session.sendString(sequence);
  }

  @override
  void dispose() {
    widget.session.disconnect();
    _terminalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _state == ZmoshState.connected
                    ? Colors.greenAccent
                    : _state == ZmoshState.disconnected
                        ? Colors.orangeAccent
                        : Colors.redAccent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.sessionTitle,
              style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'Toggle Fullscreen',
            onPressed: () {
              SystemChrome.setEnabledSystemUIMode(
                SystemUiMode.immersiveSticky,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Disconnect',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Disconnection Warning Banner
            if (_state != ZmoshState.connected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                color: _state == ZmoshState.disconnected
                    ? Colors.orange[800]
                    : Colors.red[800],
                child: Text(
                  _state == ZmoshState.disconnected
                      ? 'Reconnecting UDP link...'
                      : 'Connection lost (peer unreachable)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),

            // Terminal Screen
            Expanded(
              child: TerminalView(
                _terminal,
                controller: _terminalController,
                autofocus: true,
                backgroundOpacity: 1.0,
                textStyle: const TerminalStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ),

            // Virtual Keyboard Auxiliary Bar (Crucial for mobile shell work)
            _buildAuxiliaryKeyBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildAuxiliaryKeyBar() {
    return Container(
      height: 44,
      color: Colors.grey[950],
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        children: [
          _keyButton('ESC', () => _sendKey('\x1b')),
          _toggleButton('CTRL', _ctrlActive, () {
            setState(() => _ctrlActive = !_ctrlActive);
          }),
          _toggleButton('ALT', _altActive, () {
            setState(() => _altActive = !_altActive);
          }),
          _keyButton('TAB', () => _sendKey('\t')),
          _keyButton('▲', () => _sendKey('\x1b[A')),
          _keyButton('▼', () => _sendKey('\x1b[B')),
          _keyButton('◄', () => _sendKey('\x1b[D')),
          _keyButton('►', () => _sendKey('\x1b[C')),
          _keyButton('HOME', () => _sendKey('\x1b[H')),
          _keyButton('END', () => _sendKey('\x1b[F')),
          _keyButton('PGUP', () => _sendKey('\x1b[5~')),
          _keyButton('PGDN', () => _sendKey('\x1b[6~')),
          _keyButton('~', () => _sendKey('~')),
          _keyButton('/', () => _sendKey('/')),
          _keyButton('|', () => _sendKey('|')),
          _keyButton('-', () => _sendKey('-')),
          _keyButton('`', () => _sendKey('`')),
        ],
      ),
    );
  }

  Widget _keyButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey[850],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(36, 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _toggleButton(String label, bool active, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: active ? Colors.blueAccent : Colors.grey[850],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(36, 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
