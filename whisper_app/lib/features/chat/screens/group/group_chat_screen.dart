import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:whisper_space_flutter/features/chat/chat_api_service.dart';
import 'package:whisper_space_flutter/features/chat/model/group_model/group_details_model.dart';
import 'package:whisper_space_flutter/utils/snack_bar.dart';
import 'package:whisper_space_flutter/features/chat/model/group_model/user_model.dart';
import 'package:whisper_space_flutter/features/auth/presentation/screens/providers/auth_provider.dart';
import 'package:image_picker/image_picker.dart';

Widget _menuItem(
    BuildContext context, {
      required IconData icon,
      required String label,
      bool isDanger = false,
      VoidCallback? onTap,
    }) {
  return ListTile(
    leading: Icon(icon, color: isDanger ? Colors.red : null),
    title: Text(
      label,
      style: TextStyle(color: isDanger ? Colors.red : null),
    ),
    onTap: onTap ?? () {
      Navigator.pop(context);
      debugPrint(label);
    },
  );
}

void _close(BuildContext context, String action) {
  Navigator.pop(context);
  debugPrint(action);
}

void _confirm(BuildContext context, String title, String message) {
  Navigator.pop(context);
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            debugPrint(title);
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}

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
  final ImagePicker _picker = ImagePicker();

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

  Future<File?> _pickImage() async{
    final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85
    );
    if(picked == null) return null;
    return File(picked.path);
  }

  Future<void> _uploadCover() async {
    try{
      final file = await _pickImage();
      if (file == null) return;
      await widget.chatApi.uploadGroupCover(widget.groupId, file);
      final covers = await widget.chatApi.getGroupCovers(widget.groupId);

      setState(() {
        group!.images = covers;
      });
      
      showTopSnackBar(context, 'Cover uploaded successfully');
    }catch(e){
      showTopSnackBar(context, e.toString());
    }
  }

  Future<void> _deleteCover(int coverId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_)=> AlertDialog(
        title: const Text('Delete cover'),
        content: const Text('Delete this group cover?'),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(_, false), child: const Text('Cancel')),
          TextButton(
            onPressed: ()=> Navigator.pop(_, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          )
        ],
      )
    );
    if (confirm == true) {
      try {
        await widget.chatApi.deleteCoverById(coverId);
        setState(() {
          group!.images.removeWhere((img) => img.id == coverId);
        });
        showTopSnackBar(context, 'Cover deleted');
      } catch (e) {
        showTopSnackBar(context, e.toString());
      }
    }
  }

  Future<void> _confirmRemoveMember(UserModel member) async{
    final confirm = await showDialog(
        context: context,
        builder: (_)=> AlertDialog(
          title: const Text('Remove Member'),
          content: Text('Remove ${member.username} from this group?'),
          actions: [
            TextButton(onPressed: ()=> Navigator.pop(_, false), child: const Text('Cancel')),
            TextButton(
                onPressed: ()=> Navigator.pop(_, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Remove'))
          ],
        )
    );
    if (confirm == true) {
      try {
        await widget.chatApi.removeMember(widget.groupId, member.id);
        setState(() {
          members!.removeWhere((m) => m.id == member.id);
        });
        showTopSnackBar(context, 'Member removed');
      } catch (e) {
        showTopSnackBar(context, e.toString());
      }
    }
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave group'),
        content: const Text(
          'Are you sure you want to leave this group? You will no longer receive messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(_, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await widget.chatApi.leaveGroupById(widget.groupId);

      showTopSnackBar(context, 'You left the group');

      // Refresh chat list (remove group)
      if (widget.onRefreshChats != null) {
        await widget.onRefreshChats!();
      }

      Navigator.of(context).pop(); // dialog
      Navigator.of(context).pop(); // chat screen
    } catch (e) {
      showTopSnackBar(context, e.toString());
    }
  }

  void _showGroupDialog() {
    if (group == null) return;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.of(context).size.height * 0.8,
          child: Stack(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 80),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: DefaultTabController(
                  length: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 80),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
                        child: Text(
                          group!.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      if (group!.description != null &&
                          group!.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                          child: Text(
                            group!.description!,
                            style:
                            const TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ),

                      const SizedBox(height: 6),

                      const Padding(
                        padding: EdgeInsets.only(left: 0),
                        child: TabBar(
                          isScrollable: true,
                          labelColor: Colors.blue,
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: Colors.blue,
                          labelPadding: EdgeInsets.zero,
                          tabs: [
                            Tab(text: "All Members"),
                          ],
                        ),
                      ),

                      Expanded(
                        child: TabBarView(
                          children: [
                            ListView.builder(
                              itemCount: members?.length ?? 0,
                              itemBuilder: (context, index) {
                                final member = members![index];
                                final isAdmin = member.id == group!.creatorId;

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: member.avatarUrl != null
                                        ? NetworkImage(member.avatarUrl!)
                                        : null,
                                    backgroundColor: Colors.grey[300],
                                    child: member.avatarUrl == null
                                        ? Text(
                                      member.username[0].toUpperCase(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    )
                                        : null,
                                  ),
                                  title: Row(
                                    children: [
                                      Text(member.username),
                                      if (isAdmin)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 6),
                                          child: Text(
                                            '(Admin)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(member.email ?? ''),
                                  trailing: (_currentUserId == group!.creatorId && !isAdmin)
                                      ? IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                    onPressed: () => _confirmRemoveMember(member),
                                  )
                                      : null,
                                );
                              },
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),

              SizedBox(
                height: 180,
                width: double.infinity,
                child: group!.images.isNotEmpty
                    ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: group!.images.length,
                  itemBuilder: (context, index) {
                    final image = group!.images[index];
                    return GestureDetector(
                      key: ValueKey(image.id),
                      onLongPress: _currentUserId == group!.creatorId
                          ? () => _deleteCover(image.id)
                          : null,
                      child: Container(
                        width: MediaQuery.of(context).size.width,
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: NetworkImage(image.url),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  },
                )
                    : GestureDetector(
                  onTap: _currentUserId == group!.creatorId
                      ? _uploadCover
                      : null,
                  child: Container(
                    width: double.infinity,
                    color: Colors.grey[300],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          group!.name[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (_currentUserId == group!.creatorId)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Tap to upload cover',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                top: 16,
                left: 16,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),

              Positioned(
                top: 16,
                right: 16,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) async {
                    if (value == 'edit') {
                      _editGroupDialog();
                    }
                    else if (value == 'upload_cover') {
                      await _uploadCover();
                    }
                    else if (value == 'leave') {
                      await _leaveGroup();
                    } else if (value == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete Group'),
                          content: const Text(
                              'Are you sure you want to delete this group? This action cannot be undone.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(_, false),
                                child: const Text('Cancel')),
                            TextButton(
                                onPressed: () => Navigator.pop(_, true),
                                style:
                                TextButton.styleFrom(foregroundColor: Colors.red),
                                child: const Text('Delete')),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        try {
                          await widget.chatApi.deleteGroupId(widget.groupId);
                          showTopSnackBar(context, 'Group deleted successfully!');
                          if (widget.onRefreshChats != null) {
                            await widget.onRefreshChats!();
                          }
                          Navigator.pop(context); // close dialog
                        } catch (e) {
                          showTopSnackBar(context, 'Error deleting group: $e');
                        }
                      }
                    }
                  },
                  itemBuilder: (context) {
                    if (_currentUserId == group!.creatorId) {
                      return const [
                        PopupMenuItem(value: 'upload_cover', child: Text('Upload Cover')),
                        PopupMenuItem(value: 'edit', child: Text('Edit Group')),
                        PopupMenuItem(value: 'leave', child: Text('Leave Group')),
                        PopupMenuItem(value: 'delete', child: Text('Delete Group')),
                      ];
                    } else {
                      return const [
                        PopupMenuItem(value: 'leave', child: Text('Leave Group')),
                      ];
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editGroupDialog() {
    if (group == null) return;

    final nameController = TextEditingController(text: group!.name);
    final descriptionController = TextEditingController(text: group!.description ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Group Name'),
            ),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await widget.chatApi.updateGroupById(
                  widget.groupId,
                  name: nameController.text,
                  description: descriptionController.text.isNotEmpty
                      ? descriptionController.text
                      : null,
                );
                showTopSnackBar(context, 'Group updated successfully!');
                _loadGroup(); // Refresh the group info
                if (widget.onRefreshChats != null) await widget.onRefreshChats!();
              } catch (e) {
                showTopSnackBar(context, 'Error updating group: $e');
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            child: const Text('Save'),
          ),
        ],
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
