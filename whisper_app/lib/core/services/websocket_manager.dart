import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter/foundation.dart';
import 'package:whisper_space_flutter/core/services/storage_service.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';

class WebSocketManager {
  static final WebSocketManager _instance = WebSocketManager._internal();
  factory WebSocketManager() => _instance;
  WebSocketManager._internal();

  WebSocketChannel? _channel;
  final StorageService _storageService = StorageService();

  final StreamController<DiaryModel> _diaryStreamController = StreamController<DiaryModel>.broadcast();
  final StreamController<Map<String, dynamic>> _likeStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _commentStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _deleteStreamController = StreamController<Map<String, dynamic>>.broadcast();

  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 5;

  String _baseUrl = 'ws://10.0.2.2:8000/ws/feed'; // Android emulator
  // String _baseUrl = 'ws://localhost:8000/ws/feed'; // iOS simulator
  // String _baseUrl = 'wss://your-domain.com/ws/feed'; // production

  Stream<DiaryModel> get diaryUpdates => _diaryStreamController.stream;
  Stream<Map<String, dynamic>> get likeUpdates => _likeStreamController.stream;
  Stream<Map<String, dynamic>> get commentUpdates => _commentStreamController.stream;
  Stream<Map<String, dynamic>> get deleteUpdates => _deleteStreamController.stream;

  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionState => _connectionStateController.stream;

  Future<void> connect() async {
    if (_isConnecting || _isConnected) return;

    _isConnecting = true;
    _connectionStateController.add(false);

    try {
      final token = await _storageService.getToken();
      if (token == null) {
        print('❌ No token for WebSocket');
        _isConnecting = false;
        _scheduleReconnect();
        return;
      }

      final wsUrl = '$_baseUrl?token=$token';
      print('🔌 Connecting to: $wsUrl');

      _channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        pingInterval: const Duration(seconds: 25),
      );

      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          print('❌ WebSocket error: $error');
          _handleDisconnection();
        },
        onDone: () {
          print('🔌 WebSocket disconnected');
          _handleDisconnection();
        },
      );

      await Future.delayed(const Duration(milliseconds: 500));

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _connectionStateController.add(true);

      print('✅ WebSocket connected');

      _startHeartbeat();

      _sendMessage({
        'type': 'subscribe',
        'feed_types': ['global', 'friends', 'my'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('❌ Failed to connect WebSocket: $e');
      _handleDisconnection();
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data);
      final type = message['type'];

      print('📨 WS message: $type');

      switch (type) {
        case 'new_diary':
          _handleNewDiary(message);
          break;
        case 'diary_liked':
          _likeStreamController.add(message);
          break;
        case 'diary_commented':
          _commentStreamController.add(message);
          break;
        case 'diary_deleted':
          _deleteStreamController.add(message);
          break;
        case 'pong':
          break;
        case 'ping':
          _sendMessage({'type': 'pong'});
          break;
        case 'error':
          print('❌ WS error: ${message['error']}');
          break;
        default:
          print('⚠️ Unknown WS type: $type');
      }
    } catch (e) {
      print('❌ Error handling WS message: $e');
    }
  }

  void _handleNewDiary(Map<String, dynamic> message) {
    try {
      final diaryData = message['data'];
      final diary = DiaryModel.fromJson(diaryData);

      print('📝 New diary via WS → ID: ${diary.id}');

      _diaryStreamController.add(diary);
    } catch (e) {
      print('❌ Error parsing new diary: $e');
    }
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(message));
      } catch (e) {
        print('❌ Error sending WS message: $e');
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_isConnected) {
        _sendMessage({
          'type': 'heartbeat',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  void _handleDisconnection() {
    _isConnected = false;
    _isConnecting = false;
    _connectionStateController.add(false);

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) return;

    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 2);

    print('🔄 Reconnect in ${delay.inSeconds}s (attempt $_reconnectAttempts)');

    _reconnectTimer = Timer(delay, connect);
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();

    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }

    _isConnected = false;
    _isConnecting = false;
    _connectionStateController.add(false);
  }

  void dispose() {
    disconnect();
    _diaryStreamController.close();
    _likeStreamController.close();
    _commentStreamController.close();
    _deleteStreamController.close();
    _connectionStateController.close();
  }

  bool get isConnected => _isConnected;
}