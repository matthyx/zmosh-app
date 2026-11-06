import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../ffi/zmosh_bindings.dart';
import '../theme/app_theme.dart';

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
    final isDark = ThemeController.instance.isDark;
    final terminalTheme = isDark ? darkTerminalTheme : lightTerminalTheme;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
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
            Expanded(
              child: Text(
                widget.sessionTitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: isDark ? 'Switch to Light / E-ink Mode' : 'Switch to Dark Mode',
            onPressed: () {
              ThemeController.instance.toggleTheme();
              setState(() {});
            },
          ),
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
                theme: terminalTheme,
                backgroundOpacity: 1.0,
                textStyle: const TerminalStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ),

            // Virtual Keyboard Auxiliary Bar (Crucial for mobile shell work)
            _buildAuxiliaryKeyBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildAuxiliaryKeyBar(bool isDark) {
    return Container(
      height: 44,
      color: isDark ? const Color(0xFF181818) : const Color(0xFFE4E4E4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        children: [
          _keyButton('ESC', () => _sendKey('\x1b'), isDark),
          _toggleButton('CTRL', _ctrlActive, () {
            setState(() => _ctrlActive = !_ctrlActive);
          }, isDark),
          _toggleButton('ALT', _altActive, () {
            setState(() => _altActive = !_altActive);
          }, isDark),
          _keyButton('TAB', () => _sendKey('\t'), isDark),
          _keyButton('▲', () => _sendKey('\x1b[A'), isDark),
          _keyButton('▼', () => _sendKey('\x1b[B'), isDark),
          _keyButton('◄', () => _sendKey('\x1b[D'), isDark),
          _keyButton('►', () => _sendKey('\x1b[C'), isDark),
          _keyButton('HOME', () => _sendKey('\x1b[H'), isDark),
          _keyButton('END', () => _sendKey('\x1b[F'), isDark),
          _keyButton('PGUP', () => _sendKey('\x1b[5~'), isDark),
          _keyButton('PGDN', () => _sendKey('\x1b[6~'), isDark),
          _keyButton('~', () => _sendKey('~'), isDark),
          _keyButton('/', () => _sendKey('/'), isDark),
          _keyButton('|', () => _sendKey('|'), isDark),
          _keyButton('-', () => _sendKey('-'), isDark),
          _keyButton('`', () => _sendKey('`'), isDark),
        ],
      ),
    );
  }

  Widget _keyButton(String label, VoidCallback onPressed, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? Colors.grey[850] : Colors.white,
          foregroundColor: isDark ? Colors.white : Colors.black87,
          elevation: isDark ? 0 : 1,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(36, 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _toggleButton(String label, bool active, VoidCallback onPressed, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: active
              ? Colors.blueAccent
              : (isDark ? Colors.grey[850] : Colors.white),
          foregroundColor: active ? Colors.white : (isDark ? Colors.white : Colors.black87),
          elevation: isDark ? 0 : 1,
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
