import 'dart:async';
import 'package:flutter/material.dart';
import 'package:whisper_space_flutter/core/services/storage_service.dart';
import 'package:whisper_space_flutter/features/websocket/group_websocket.dart';
import 'package:whisper_space_flutter/features/chat/model/group_message_model/group_message_model.dart';
import '../../chat_api_service.dart';

class GroupMessageScreen extends StatefulWidget {
  final int groupId;
  final int currentUserId;
  final GroupWebsocket groupWebsocket;
  final StorageService storageService;
  final ChatAPISource chatApi;

  const GroupMessageScreen(
      {super.key,
      required this.groupId,
      required this.currentUserId,
      required this.groupWebsocket,
      required this.storageService,
      required this.chatApi});

  @override
  State<GroupMessageScreen> createState() => _GroupMessageScreenState();
}

class _GroupMessageScreenState extends State<GroupMessageScreen> {
  List<GroupMessageModel> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final StreamSubscription _wsSubscription;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOldMessages();
    _wsSubscription = widget.groupWebsocket.stream.listen(
      (jsonData) {
        _handleWsEvent(jsonData);
      },
      onError: (error) {
        debugPrint('WebSocket stream error: $error');
      },
      onDone: () {
        debugPrint('WebSocket stream closed');
      },
    );
  }

  @override
  void dispose() {
    _wsSubscription.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleWsEvent(Map<String, dynamic> data) {
    final action = data['action'];

    switch (action) {
      case 'pong':
      case 'online_users':
        return;

      case 'delete':
        setState(() {
          _messages.removeWhere((m) => m.id == data['message_id']);
        });
        return;

      case 'edit':
        setState(() {
          final index = _messages.indexWhere(
            (m) => m.id == data['message_id'],
          );
          if (index != -1) {
            _messages[index] =
                _messages[index].copyWith(content: data['new_content']);
          }
        });
        return;

      default:
        final message = GroupMessageModel.fromJson(data);
        setState(() => _messages.add(message));
        _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _loadOldMessages() async {
    try {
      final data = await widget.chatApi.getGroupMessage(widget.groupId);

      debugPrint('message data: $data');

      setState(() {
        _messages = data;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Failed to load messages: $e');
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    widget.groupWebsocket.sendMessage(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      children: [
        Expanded(
            child: ListView.builder(
                controller: _scrollController,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isMe = msg.sender.id == widget.currentUserId;

                  return Align(
                    alignment:
                        isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: isMe
                              ? Colors.blueAccent.withOpacity(0.8)
                              : Colors.grey.shade300),
                      child: Text(
                        msg.content ?? '',
                        style: TextStyle(
                            color: isMe ? Colors.white : Colors.black),
                      ),
                    ),
                  );
                })),
        SafeArea(
            child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                  child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                    hintText: 'Aa...', border: OutlineInputBorder()),
              )),
              const SizedBox(
                width: 8,
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendMessage,
              )
            ],
          ),
        ))
      ],
    );
  }
}
