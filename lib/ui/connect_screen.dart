import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ffi/zmosh_bindings.dart';
import '../services/ssh_bootstrap.dart';
import 'terminal_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _formKey = GlobalKey<FormState>();

  final _hostController = TextEditingController();
  final _sshPortController = TextEditingController(text: '22');
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _sessionController = TextEditingController(text: 'main');

  bool _isConnecting = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedConnection();
  }

  Future<void> _loadSavedConnection() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostController.text = prefs.getString('last_host') ?? '';
      _sshPortController.text = prefs.getString('last_ssh_port') ?? '22';
      _userController.text = prefs.getString('last_user') ?? '';
      _sessionController.text = prefs.getString('last_session') ?? 'main';
    });
  }

  Future<void> _saveConnection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_host', _hostController.text.trim());
    await prefs.setString('last_ssh_port', _sshPortController.text.trim());
    await prefs.setString('last_user', _userController.text.trim());
    await prefs.setString('last_session', _sessionController.text.trim());
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
      final sessionName = _sessionController.text.trim();

      await _saveConnection();

      // Step 1: Bootstrap zmosh serve over SSH to obtain ephemeral UDP port and key
      final bootstrap = await SshBootstrap.bootstrap(
        host: host,
        port: sshPort,
        username: user,
        password: password,
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
        rows: 24,
        cols: 80,
        onOutput: (_) {},
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
                        hintText: '192.168.1.100 or server.lan',
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
                  hintText: 'e.g. mbertschy',
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
                  labelText: 'Password (or leave blank for SSH agent/key)',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Session Name
              TextFormField(
                controller: _sessionController,
                decoration: const InputDecoration(
                  labelText: 'zmx Session Name',
                  hintText: 'main',
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
