import 'dart:io';

import 'package:flutter/material.dart';
import 'package:whisper_space_flutter/features/chat/model/group_model/group_details_model.dart';
import 'package:whisper_space_flutter/features/chat/model/group_model/user_model.dart';
import 'package:whisper_space_flutter/features/chat/chat_api_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:whisper_space_flutter/utils/snack_bar.dart';

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
    onTap: onTap ??
        () {
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

class GroupDialogPage extends StatefulWidget {
  final GroupDetailsModel group;
  final List<UserModel> members;
  final int currentUserId;
  final ChatAPISource chatApi;
  final Future<void> Function()? onRefreshChats;
  final VoidCallback onGroupUpdated;

  const GroupDialogPage({
    super.key,
    required this.group,
    required this.members,
    required this.currentUserId,
    required this.chatApi,
    this.onRefreshChats,
    required this.onGroupUpdated,
  });

  @override
  State<GroupDialogPage> createState() => _GroupDialogPageState();
}

class _GroupDialogPageState extends State<GroupDialogPage> {
  late GroupDetailsModel group;
  late List<UserModel> members;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    group = widget.group;
    members = widget.members;
  }

  Future<void> _uploadCover() async {
    final XFile? picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final file = File(picked.path);
    try {
      await widget.chatApi.uploadGroupCover(group.id, file);
      final covers = await widget.chatApi.getGroupCovers(group.id);
      setState(() => group.images = covers);
      widget.onGroupUpdated();
    } catch (e) {
      showTopSnackBar(context, e.toString());
    }
  }

  Future<void> _deleteCover(int coverId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete cover'),
        content: const Text('Delete this group cover?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(_, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.chatApi.deleteCoverById(coverId);
        setState(() => group.images.removeWhere((img) => img.id == coverId));
        widget.onGroupUpdated();
        showTopSnackBar(context, 'Cover deleted');
      } catch (e) {
        showTopSnackBar(context, e.toString());
      }
    }
  }

  Future<void> _confirmRemoveMember(UserModel member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.username} from this group?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(_, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.chatApi.removeMember(group.id, member.id);
        setState(() => members.removeWhere((m) => m.id == member.id));
        widget.onGroupUpdated();
        showTopSnackBar(context, 'Member removed');
      } catch (e) {
        showTopSnackBar(context, e.toString());
      }
    }
  }

  void _editGroupDialog() {
    final nameController = TextEditingController(text: group.name);
    final descriptionController =
        TextEditingController(text: group.description ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Group Name')),
            TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await widget.chatApi.updateGroupById(
                  group.id,
                  name: nameController.text,
                  description: descriptionController.text.isNotEmpty
                      ? descriptionController.text
                      : null,
                );
                showTopSnackBar(context, 'Group updated successfully!');
                widget.onGroupUpdated();
                if (widget.onRefreshChats != null) {
                  await widget.onRefreshChats!();
                }
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
      await widget.chatApi.leaveGroupById(widget.group.id);
      showTopSnackBar(context, 'You left the group');
      if (widget.onRefreshChats != null) {
        await widget.onRefreshChats!();
      }
      Navigator.of(context).pop();
      Navigator.of(context).pop();
    } catch (e) {
      showTopSnackBar(context, e.toString());
    }
  }

  Future<void> _deleteGroup() async{
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
        await widget.chatApi.deleteGroupId(widget.group.id);
        showTopSnackBar(context, 'Group deleted successfully!');
        if (widget.onRefreshChats != null) {
          await widget.onRefreshChats!();
        }
        Navigator.of(context).pop();
        Navigator.of(context).pop();
      } catch (e) {
        showTopSnackBar(context, 'Error deleting group: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1, // Only "All Members" for now
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Group Cover
                  SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: group.images.isNotEmpty
                        ? ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: group.images.length,
                            itemBuilder: (context, index) {
                              final image = group.images[index];
                              return GestureDetector(
                                key: ValueKey(image.id),
                                onLongPress:
                                    widget.currentUserId == group.creatorId
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
                            onTap: widget.currentUserId == group.creatorId
                                ? _uploadCover
                                : null,
                            child: Container(
                              width: double.infinity,
                              color: Colors.grey[300],
                              child: Center(
                                child: Text(
                                  group.name[0].toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),

                  // Group Info
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group.name,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold)),
                        if (group.description != null &&
                            group.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(group.description!,
                                style: const TextStyle(
                                    fontSize: 16, color: Colors.grey)),
                          ),
                      ],
                    ),
                  ),

                  // Tabs
                  const TabBar(
                    labelColor: Colors.blue,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.blue,
                    tabs: [Tab(text: 'All Members')],
                  ),

                  // Tab content
                  Expanded(
                    child: TabBarView(
                      children: [
                        ListView.builder(
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            final member = members[index];
                            final isAdmin = member.id == group.creatorId;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: member.avatarUrl != null
                                    ? NetworkImage(member.avatarUrl!)
                                    : null,
                                backgroundColor: Colors.grey[300],
                                child: member.avatarUrl == null
                                    ? Text(member.username[0].toUpperCase(),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold))
                                    : null,
                              ),
                              title: Row(
                                children: [
                                  Text(member.username),
                                  if (isAdmin)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 6),
                                      child: Text('(Admin)',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue)),
                                    ),
                                ],
                              ),
                              subtitle: Text(member.email ?? ''),
                              trailing:
                                  widget.currentUserId == group.creatorId &&
                                          !isAdmin
                                      ? PopupMenuButton<String>(
                                          onSelected: (value) {
                                            if (value == 'remove')
                                              _confirmRemoveMember(member);
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                                value: 'remove',
                                                child: Text('Remove Member')),
                                          ],
                                        )
                                      : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Back button
              Positioned(
                top: 16,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),
              ),

              // Group actions
              Positioned(
                top: 16,
                right: 16,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    if (value == 'edit') _editGroupDialog();
                    if (value == 'upload_cover') await _uploadCover();
                    if (value == 'leave') await _leaveGroup();
                    if (value == 'delete') await _deleteGroup();
                  },
                  itemBuilder: (_) => widget.currentUserId == group.creatorId
                      ? const [
                          PopupMenuItem(
                              value: 'upload_cover',
                              child: Text('Upload Cover')),
                          PopupMenuItem(
                              value: 'edit', child: Text('Edit Group')),
                          PopupMenuItem(
                              value: 'leave', child: Text('Leave Group')),
                          PopupMenuItem(
                              value: 'delete', child: Text('Delete Group')),
                        ]
                      : const [
                          PopupMenuItem(
                              value: 'leave', child: Text('Leave Group')),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
