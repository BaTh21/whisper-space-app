// lib/core/services/websocket_manager.dart
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter/foundation.dart';
import 'package:whisper_space_flutter/core/services/storage_service.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import 'package:whisper_space_flutter/features/auth/data/models/user_model.dart';

class WebSocketManager {
  static final WebSocketManager _instance = WebSocketManager._internal();
  factory WebSocketManager() => _instance;
  WebSocketManager._internal();

  WebSocketChannel? _channel;
  final StorageService _storageService = StorageService();
  
  // Stream controllers for different types of updates
  final StreamController<DiaryModel> _diaryStreamController = StreamController<DiaryModel>.broadcast();
  final StreamController<Map<String, dynamic>> _likeStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _commentStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _deleteStreamController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Connection state
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 5;
  
  // Configuration
  String _baseUrl = 'ws://10.0.2.2:8000/ws/feed'; // For Android emulator
  // String _baseUrl = 'ws://localhost:8000/ws/feed'; // For iOS simulator
  // String _baseUrl = 'wss://your-domain.com/ws/feed'; // For production
  
  // Getters for streams
  Stream<DiaryModel> get diaryUpdates => _diaryStreamController.stream;
  Stream<Map<String, dynamic>> get likeUpdates => _likeStreamController.stream;
  Stream<Map<String, dynamic>> get commentUpdates => _commentStreamController.stream;
  Stream<Map<String, dynamic>> get deleteUpdates => _deleteStreamController.stream;
  
  // Connection state stream
  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionState => _connectionStateController.stream;
  
  Future<void> connect() async {
    if (_isConnecting || _isConnected) return;
    
    _isConnecting = true;
    _connectionStateController.add(false);
    
    try {
      final token = await _storageService.getToken();
      if (token == null) {
        print('❌ No token available for WebSocket connection');
        _isConnecting = false;
        _scheduleReconnect();
        return;
      }

      // Construct WebSocket URL
      final wsUrl = '$_baseUrl?token=$token';
      print('🔌 Connecting to WebSocket: $wsUrl');
      
      // Create WebSocket connection
      _channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        pingInterval: const Duration(seconds: 25),
      );
      
      // Listen for messages
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

      // Wait for connection to be established
      await Future.delayed(const Duration(milliseconds: 500));
      
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _connectionStateController.add(true);
      
      print('✅ WebSocket connected successfully');
      
      // Start heartbeat
      _startHeartbeat();
      
      // Subscribe to feed updates
      _sendMessage({
        'type': 'subscribe',
        'feed_types': ['global', 'friends', 'my'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
    } catch (e) {
      print('❌ Failed to connect to WebSocket: $e');
      _handleDisconnection();
    }
  }
  
  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data);
      final type = message['type'];
      
      if (kDebugMode) {
        print('📨 WebSocket message: $type');
      }
      
      switch (type) {
        case 'auth_success':
          print('✅ WebSocket authenticated');
          break;
          
        case 'new_diary':
          _handleNewDiary(message);
          break;
          
        case 'diary_liked':
          _handleDiaryLike(message);
          break;
          
        case 'diary_commented':
          _handleDiaryComment(message);
          break;
          
        case 'diary_deleted':
          _handleDiaryDelete(message);
          break;
          
        case 'pong':
          // Heartbeat response, do nothing
          break;
          
        case 'ping':
          // Respond to server ping
          _sendMessage({'type': 'pong'});
          break;
          
        case 'connection_info':
          print('🔗 WebSocket connection info: ${message['status']}');
          break;
          
        case 'subscription_confirmed':
          print('✅ Subscribed to feed updates');
          break;
          
        case 'error':
          print('❌ WebSocket error: ${message['error']}');
          break;
          
        default:
          print('⚠️ Unknown WebSocket message type: $type');
      }
    } catch (e) {
      print('❌ Error handling WebSocket message: $e');
      if (kDebugMode) {
        print('Raw data: $data');
      }
    }
  }
  
  void _handleNewDiary(Map<String, dynamic> message) {
    try {
      final diaryData = message['data'];
      final diary = DiaryModel.fromJson(diaryData);
      
      if (kDebugMode) {
        print('📝 New diary received: ${diary.id} - ${diary.title}');
      }
      
      _diaryStreamController.add(diary);
      
    } catch (e) {
      print('❌ Error parsing new diary: $e');
    }
  }
  
  void _handleDiaryLike(Map<String, dynamic> message) {
    try {
      final diaryId = message['diary_id'];
      final userId = message['user_id'];
      final username = message['user_username'];
      
      if (kDebugMode) {
        print('❤️ Like received for diary $diaryId from user $username');
      }
      
      _likeStreamController.add({
        'diary_id': diaryId,
        'user_id': userId,
        'user_username': username,
        'timestamp': message['timestamp'],
      });
      
    } catch (e) {
      print('❌ Error parsing like: $e');
    }
  }
  
  void _handleDiaryComment(Map<String, dynamic> message) {
    try {
      final diaryId = message['diary_id'];
      final comment = message['comment'];
      
      if (kDebugMode) {
        print('💬 Comment received for diary $diaryId');
      }
      
      _commentStreamController.add({
        'diary_id': diaryId,
        'comment': comment,
        'timestamp': message['timestamp'],
      });
      
    } catch (e) {
      print('❌ Error parsing comment: $e');
    }
  }
  
  void _handleDiaryDelete(Map<String, dynamic> message) {
    try {
      final diaryId = message['diary_id'];
      
      if (kDebugMode) {
        print('🗑️ Diary deleted: $diaryId');
      }
      
      _deleteStreamController.add({
        'diary_id': diaryId,
        'timestamp': message['timestamp'],
      });
      
    } catch (e) {
      print('❌ Error parsing delete: $e');
    }
  }
  
  void _sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(message));
      } catch (e) {
        print('❌ Error sending WebSocket message: $e');
      }
    }
  }
  
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
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
    
    // Close channel
    if (_channel != null) {
      try {
        _channel!.sink.close();
      } catch (e) {
        print('Error closing WebSocket: $e');
      }
      _channel = null;
    }
    
    // Schedule reconnection
    _scheduleReconnect();
  }
  
  void _scheduleReconnect() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      return;
    }
    
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('❌ Max reconnection attempts reached');
      return;
    }
    
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 2);
    
    print('🔄 Scheduling reconnection in ${delay.inSeconds} seconds (attempt $_reconnectAttempts)');
    
    _reconnectTimer = Timer(delay, () {
      print('🔄 Attempting to reconnect...');
      connect();
    });
  }
  
  Future<void> disconnect() async {
    print('🔌 Disconnecting WebSocket...');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    
    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }
    
    _isConnected = false;
    _isConnecting = false;
    _connectionStateController.add(false);
    
    print('✅ WebSocket disconnected');
  }
  
  // Send a new diary (for testing or if you want to broadcast from client)
  void broadcastNewDiary(DiaryModel diary) {
    _sendMessage({
      'type': 'new_diary',
      'data': diary.toJson(),
    });
  }
  
  void broadcastLike(int diaryId) {
    _sendMessage({
      'type': 'diary_liked',
      'diary_id': diaryId,
    });
  }
  
  void broadcastComment(int diaryId, Map<String, dynamic> comment) {
    _sendMessage({
      'type': 'diary_commented',
      'diary_id': diaryId,
      'comment': comment,
    });
  }
  
  void broadcastDelete(int diaryId) {
    _sendMessage({
      'type': 'diary_deleted',
      'diary_id': diaryId,
    });
  }
  
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  
  void updateBaseUrl(String baseUrl) {
    _baseUrl = baseUrl;
    disconnect();
    connect();
  }
  
  void dispose() {
    disconnect();
    _diaryStreamController.close();
    _likeStreamController.close();
    _commentStreamController.close();
    _deleteStreamController.close();
    _connectionStateController.close();
  }
}