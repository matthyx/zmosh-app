import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ffi/zmosh_bindings.dart';
import '../services/ssh_bootstrap.dart';
import '../theme/app_theme.dart';
import 'terminal_screen.dart';

const String defaultTabletKey = '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACCLvRTh1ypyzCH+QSRJ9f8X1a/lenvYeHEvuoKaGAxmQwAAAJBpzl1Zac5d
WQAAAAtzc2gtZWQyNTUxOQAAACCLvRTh1ypyzCH+QSRJ9f8X1a/lenvYeHEvuoKaGAxmQw
AAAECkoa9xKx9fFwiGmF8EQQLxghDe8FNivp3BM8s6ca8xgIu9FOHXKnLMIf5BJEn1/xfV
r+V6e9h4cS+6gpoYDGZDAAAADHptb3NoLXRhYmxldAE=
-----END OPENSSH PRIVATE KEY-----''';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _formKey = GlobalKey<FormState>();

  final _hostController = TextEditingController(text: '192.168.88.250');
  final _sshPortController = TextEditingController(text: '22');
  final _userController = TextEditingController(text: 'mbertschy');
  final _passwordController = TextEditingController();
  final _keyController = TextEditingController();
  final _sessionController = TextEditingController(text: 'tablet');

  bool _isConnecting = false;
  bool _showKeyInput = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedConnection();
  }

  static File get _configFile => File('/sdcard/Android/data/com.matthyx.zmosh/files/config.json');

  Future<void> _loadSavedConnection() async {
    final prefs = await SharedPreferences.getInstance();
    String host = prefs.getString('host') ?? '192.168.88.250';
    String port = prefs.getString('port') ?? '22';
    String user = prefs.getString('user') ?? 'mbertschy';
    String session = prefs.getString('session') ?? 'tablet';
    String keyContent = prefs.getString('private_key') ?? defaultTabletKey;

    try {
      if (await _configFile.exists()) {
        final data = jsonDecode(await _configFile.readAsString()) as Map<String, dynamic>;
        host = data['host'] ?? host;
        port = data['port'] ?? port;
        user = data['user'] ?? user;
        session = data['session'] ?? session;
        keyContent = data['private_key'] ?? keyContent;
      }
    } catch (_) {}

    setState(() {
      _hostController.text = host;
      _sshPortController.text = port;
      _userController.text = user;
      _sessionController.text = session;
      _keyController.text = keyContent.trim();
      _showKeyInput = true;
    });
  }

  Future<void> _saveConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('host', _hostController.text.trim());
      await prefs.setString('port', _sshPortController.text.trim());
      await prefs.setString('user', _userController.text.trim());
      await prefs.setString('session', _sessionController.text.trim());
      await prefs.setString('private_key', _keyController.text.trim());

      final data = {
        'host': _hostController.text.trim(),
        'port': _sshPortController.text.trim(),
        'user': _userController.text.trim(),
        'session': _sessionController.text.trim(),
        'private_key': _keyController.text.trim(),
      };
      await _configFile.parent.create(recursive: true);
      await _configFile.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting SSH & bootstrapping zmosh gateway...';
    });

    try {
      final host = _hostController.text.trim();
      final sshPort = int.tryParse(_sshPortController.text.trim()) ?? 22;
      final user = _userController.text.trim();
      final password = _passwordController.text.isEmpty ? null : _passwordController.text;
      final privateKey = _keyController.text.trim().isEmpty ? null : _keyController.text.trim();
      final sessionName = _sessionController.text.trim();

      await _saveConnection();

      // Step 1: Bootstrap zmosh serve over SSH to obtain ephemeral UDP port and key
      final bootstrap = await SshBootstrap.bootstrap(
        host: host,
        port: sshPort,
        username: user,
        password: password,
        privateKey: privateKey,
        sessionName: sessionName,
      );

      setState(() {
        _statusMessage = 'Establishing authenticated UDP link (port ${bootstrap.udpPort})...';
      });

      // Step 2: Connect native libzmosh session over UDP
      final session = ZmoshSession.connect(
        host: host,
        port: bootstrap.udpPort,
        keyBase64: bootstrap.keyBase64,
        rows: 40,
        cols: 100,
      );

      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _statusMessage = null;
      });

      // Step 3: Navigate to terminal screen
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TerminalScreen(
            session: session,
            sessionTitle: '$user@$host ($sessionName)',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _statusMessage = null;
        });
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Connection Error'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('zmosh mobile'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(ThemeController.instance.isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: ThemeController.instance.isDark ? 'Switch to Light / E-ink Mode' : 'Switch to Dark Mode',
            onPressed: () {
              ThemeController.instance.toggleTheme();
              setState(() {});
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo / Icon header
              const Icon(
                Icons.terminal_rounded,
                size: 72,
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect to zmx multiplexer',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              // Host & SSH Port row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _hostController,
                      decoration: const InputDecoration(
                        labelText: 'Remote Host',
                        hintText: '192.168.88.250',
                        prefixIcon: Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty ? 'Enter host' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _sshPortController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Username
              TextFormField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'mbertschy',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Enter username' : null,
              ),
              const SizedBox(height: 16),

              // Password
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password (leave blank if using SSH key)',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // SSH Key Section
              Card(
                color: Colors.grey[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _keyController.text.isNotEmpty
                                    ? Icons.vpn_key
                                    : Icons.vpn_key_outlined,
                                color: _keyController.text.isNotEmpty
                                    ? Colors.greenAccent
                                    : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _keyController.text.isNotEmpty
                                    ? 'SSH Key Loaded (Ed25519)'
                                    : 'SSH Private Key (Optional)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _keyController.text.isNotEmpty
                                      ? Colors.greenAccent
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() => _showKeyInput = !_showKeyInput);
                            },
                            child: Text(_showKeyInput ? 'Hide' : 'Edit'),
                          ),
                        ],
                      ),
                      if (_showKeyInput) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _keyController,
                          maxLines: 4,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                          decoration: const InputDecoration(
                            hintText: 'Paste PEM private key (-----BEGIN OPENSSH PRIVATE KEY-----)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Session Name
              TextFormField(
                controller: _sessionController,
                decoration: const InputDecoration(
                  labelText: 'zmx Session Name',
                  hintText: 'tablet',
                  prefixIcon: Icon(Icons.tab_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Enter session name' : null,
              ),
              const SizedBox(height: 28),

              // Connect Button
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isConnecting ? null : _connect,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.login),
                label: Text(
                  _isConnecting ? 'Connecting...' : 'Connect',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),

              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[400],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
