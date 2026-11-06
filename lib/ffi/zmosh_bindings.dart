import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';

// Status codes returned by libzmosh
enum ZmoshStatus {
  ok,
  errResolve,
  errSocket,
  errInvalidKey,
  errDisconnected,
  errDead,
  errPoll,
  errNull,
  errSend,
  errTooLarge,
}

// Connection states
enum ZmoshState {
  connected,
  disconnected,
  dead,
}

// C API types
final class OpaqueSession extends Opaque {}

typedef OutputCallbackC = Void Function(Pointer<Void> ctx, Pointer<Uint8> data, Uint32 len);
typedef StateCallbackC = Void Function(Pointer<Void> ctx, Int32 state);
typedef EndCallbackC = Void Function(Pointer<Void> ctx);

typedef ZmoshConnectC = Pointer<OpaqueSession> Function(
  Pointer<Utf8> host,
  Uint16 port,
  Pointer<Utf8> keyBase64,
  Uint16 rows,
  Uint16 cols,
  Pointer<NativeFunction<OutputCallbackC>> outputCb,
  Pointer<NativeFunction<StateCallbackC>> stateCb,
  Pointer<NativeFunction<EndCallbackC>> endCb,
  Pointer<Void> ctx,
  Pointer<Int32> status,
);

typedef ZmoshConnectDart = Pointer<OpaqueSession> Function(
  Pointer<Utf8> host,
  int port,
  Pointer<Utf8> keyBase64,
  int rows,
  int cols,
  Pointer<NativeFunction<OutputCallbackC>> outputCb,
  Pointer<NativeFunction<StateCallbackC>> stateCb,
  Pointer<NativeFunction<EndCallbackC>> endCb,
  Pointer<Void> ctx,
  Pointer<Int32> status,
);

typedef ZmoshGetFdC = Int32 Function(Pointer<OpaqueSession> session);
typedef ZmoshGetFdDart = int Function(Pointer<OpaqueSession> session);

typedef ZmoshPollC = Int32 Function(Pointer<OpaqueSession> session);
typedef ZmoshPollDart = int Function(Pointer<OpaqueSession> session);

typedef ZmoshSendInputC = Int32 Function(Pointer<OpaqueSession> session, Pointer<Uint8> data, Uint32 len);
typedef ZmoshSendInputDart = int Function(Pointer<OpaqueSession> session, Pointer<Uint8> data, int len);

typedef ZmoshResizeC = Int32 Function(Pointer<OpaqueSession> session, Uint16 rows, Uint16 cols);
typedef ZmoshResizeDart = int Function(Pointer<OpaqueSession> session, int rows, int cols);

typedef ZmoshDisconnectC = Void Function(Pointer<OpaqueSession> session);
typedef ZmoshDisconnectDart = void Function(Pointer<OpaqueSession> session);

/// Dynamic library loader for libzmosh
class ZmoshLibrary {
  static final ZmoshLibrary instance = ZmoshLibrary._();
  late final DynamicLibrary _lib;

  late final ZmoshConnectDart zmoshConnect;
  late final ZmoshGetFdDart zmoshGetFd;
  late final ZmoshPollDart zmoshPoll;
  late final ZmoshSendInputDart zmoshSendInput;
  late final ZmoshResizeDart zmoshResize;
  late final ZmoshDisconnectDart zmoshDisconnect;

  ZmoshLibrary._() {
    _lib = _openLibrary();
    zmoshConnect = _lib.lookupFunction<ZmoshConnectC, ZmoshConnectDart>('zmosh_connect');
    zmoshGetFd = _lib.lookupFunction<ZmoshGetFdC, ZmoshGetFdDart>('zmosh_get_fd');
    zmoshPoll = _lib.lookupFunction<ZmoshPollC, ZmoshPollDart>('zmosh_poll');
    zmoshSendInput = _lib.lookupFunction<ZmoshSendInputC, ZmoshSendInputDart>('zmosh_send_input');
    zmoshResize = _lib.lookupFunction<ZmoshResizeC, ZmoshResizeDart>('zmosh_resize');
    zmoshDisconnect = _lib.lookupFunction<ZmoshDisconnectC, ZmoshDisconnectDart>('zmosh_disconnect');
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid || Platform.isLinux) {
      try {
        return DynamicLibrary.open('libzmosh.so');
      } catch (_) {
        return DynamicLibrary.process();
      }
    } else if (Platform.isMacOS || Platform.isIOS) {
      try {
        return DynamicLibrary.open('libzmosh.dylib');
      } catch (_) {
        return DynamicLibrary.process();
      }
    }
    throw UnsupportedError('Unsupported operating system: ${Platform.operatingSystem}');
  }
}

/// High level session management wrapping the native C API
class ZmoshSession {
  final ZmoshLibrary _lib = ZmoshLibrary.instance;
  Pointer<OpaqueSession>? _session;
  Timer? _pollTimer;

  final void Function(List<int> bytes) onOutput;
  final void Function(ZmoshState state)? onStateChanged;
  final void Function()? onSessionEnded;

  static ZmoshSession? _activeSession;

  ZmoshSession._({
    required this.onOutput,
    this.onStateChanged,
    this.onSessionEnded,
  });

  static void _staticOutputCallback(Pointer<Void> ctx, Pointer<Uint8> data, int len) {
    if (_activeSession != null && len > 0) {
      final list = data.asTypedList(len);
      _activeSession!.onOutput(List<int>.from(list));
    }
  }

  static void _staticStateCallback(Pointer<Void> ctx, int state) {
    if (_activeSession?.onStateChanged != null) {
      final s = state >= 0 && state < ZmoshState.values.length
          ? ZmoshState.values[state]
          : ZmoshState.disconnected;
      _activeSession!.onStateChanged!(s);
    }
  }

  static void _staticEndCallback(Pointer<Void> ctx) {
    _activeSession?.onSessionEnded?.call();
  }

  /// Establish UDP link to remote zmosh daemon
  static ZmoshSession connect({
    required String host,
    required int port,
    required String keyBase64,
    required int rows,
    required int cols,
    required void Function(List<int> bytes) onOutput,
    void Function(ZmoshState state)? onStateChanged,
    void Function()? onSessionEnded,
  }) {
    final session = ZmoshSession._(
      onOutput: onOutput,
      onStateChanged: onStateChanged,
      onSessionEnded: onSessionEnded,
    );

    _activeSession = session;

    final hostPtr = host.toNativeUtf8();
    final keyPtr = keyBase64.toNativeUtf8();
    final statusPtr = calloc<Int32>();

    final outputNative = Pointer.fromFunction<OutputCallbackC>(_staticOutputCallback);
    final stateNative = Pointer.fromFunction<StateCallbackC>(_staticStateCallback);
    final endNative = Pointer.fromFunction<EndCallbackC>(_staticEndCallback);

    try {
      final s = session._lib.zmoshConnect(
        hostPtr,
        port,
        keyPtr,
        rows,
        cols,
        outputNative,
        stateNative,
        endNative,
        nullptr,
        statusPtr,
      );

      final statusVal = statusPtr.value;
      if (s == nullptr || statusVal != 0) {
        final err = statusVal >= 0 && statusVal < ZmoshStatus.values.length
            ? ZmoshStatus.values[statusVal]
            : ZmoshStatus.errSocket;
        throw Exception('Failed to connect to zmosh server: $err');
      }

      session._session = s;
      session._startPolling();
      return session;
    } finally {
      calloc.free(hostPtr);
      calloc.free(keyPtr);
      calloc.free(statusPtr);
    }
  }

  void _startPolling() {
    // 50Hz polling loop (~20ms) for high responsiveness over UDP
    _pollTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (_session == null || _session == nullptr) return;
      _lib.zmoshPoll(_session!);
    });
  }

  /// Send user input keys to remote zmx session
  void sendInput(List<int> bytes) {
    if (_session == null || _session == nullptr || bytes.isEmpty) return;
    final ptr = calloc<Uint8>(bytes.length);
    try {
      for (var i = 0; i < bytes.length; i++) {
        ptr[i] = bytes[i];
      }
      _lib.zmoshSendInput(_session!, ptr, bytes.length);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Send UTF-8 text string to remote session
  void sendString(String text) {
    sendInput(utf8.encode(text));
  }

  /// Send terminal resize update
  void resize(int rows, int cols) {
    if (_session == null || _session == nullptr) return;
    _lib.zmoshResize(_session!, rows, cols);
  }

  /// Disconnect session and release resources
  void disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_session != null && _session != nullptr) {
      _lib.zmoshDisconnect(_session!);
      _session = null;
    }
    if (_activeSession == this) {
      _activeSession = null;
    }
  }
}
