import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:whisper_space_flutter/features/chat/chat_api_service.dart';
import 'package:whisper_space_flutter/features/chat/model/group_model/group_details_model.dart';
import 'package:whisper_space_flutter/features/chat/model/group_model/user_model.dart';
import 'package:whisper_space_flutter/features/auth/presentation/screens/providers/auth_provider.dart';
import 'group_dialog/group_dialog_page.dart';

class GroupChatScreen extends StatefulWidget {
  final int groupId;
  final String groupName;
  final String? groupCover;
  final ChatAPISource chatApi;
  final Future<void> Function()? onRefreshChats;

  const GroupChatScreen({super.key,
    required this.groupId,
    required this.groupName,
    this.groupCover,
    required this.chatApi, this.onRefreshChats
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  int? _currentUserId;
  GroupDetailsModel? group;
  List<UserModel>? members = [];

  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadGroup();
  }

  void _loadCurrentUser() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;
      if (user != null) {
        setState(() {
          _currentUserId = user.id;
        });
      }
    });
  }

  Future<void> _loadCovers() async {
    try {
      final covers = await widget.chatApi.getGroupCovers(widget.groupId);
      setState(() {
        group!.images = covers;
      });
    } catch (_) {}
  }

  Future<void> _loadGroup() async {
    try {
      final result = await widget.chatApi.getGroupById(widget.groupId);
      final memberData = await widget.chatApi.getGroupMembers(widget.groupId);
      setState(() {
        group = result;
        members= memberData;
        isLoading = false;
      });
      await _loadCovers();
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  void _showGroupDialog() {
    if (group == null) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => GroupDialogPage(
          group: group!,
          members: members!,
          currentUserId: _currentUserId!,
          chatApi: widget.chatApi,
          onRefreshChats: widget.onRefreshChats,
          onGroupUpdated: _loadGroup,
        ),
        transitionsBuilder: (_, animation, __, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeInOut));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (error != null) {
      return Scaffold(body: Center(child: Text(error!)));
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _showGroupDialog,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child:
                CircleAvatar(
                  radius: 18,
                  backgroundImage: group!.cover != null
                      ? NetworkImage(group!.cover!)
                      : null,
                  backgroundColor: Colors.grey[300],
                  child: group!.cover == null
                      ? Text(group!.name[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold))
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(group!.name),
            ],
          ),
        ),
      ),
      body: Center(child: Text('Group chat ${group!.name}')),
    );
  }
}
