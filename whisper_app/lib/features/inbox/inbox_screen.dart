import 'package:flutter/material.dart';
import 'package:whisper_space_flutter/core/services/storage_service.dart';
import 'package:whisper_space_flutter/features/inbox/inbox_model/inbox_model.dart';
import 'inbox_api_service.dart';
import 'package:whisper_space_flutter/utils/snack_bar.dart';

class InboxDialog extends StatefulWidget {
  final int? unreadCounts;

  const InboxDialog({super.key, this.unreadCounts});

  @override
  State<InboxDialog> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxDialog>
    with SingleTickerProviderStateMixin {
  late final InboxAPISource inboxApi;
  List<InboxModel> inboxs = [];
  Set<int> _selectedIds = {};
  bool _selectionMode = false;

  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;
  String? error;

  int limit = 20;
  int offset = 0;

  late final ScrollController _scrollController;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    initServicesAndLoad();
  }

  Future<void> initServicesAndLoad() async {
    final storageService = StorageService();
    await storageService.init();

    inboxApi = InboxAPISource(storageService: storageService);

    await _loadInboxs();
  }

  Future<void> _loadInboxs() async {
    if (!hasMore) return;

    try {
      if (offset == 0) {
        setState(() {
          isLoading = true;
        });
      } else {
        setState(() {
          isLoadingMore = true;
        });
      }

      final data = await inboxApi.getActivities(limit: limit, offset: offset);

      setState(() {
        inboxs.addAll(data);
        offset += data.length;
        isLoading = false;
        isLoadingMore = false;
        if (data.length < limit) {
          hasMore = false; // No more data
        }
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
        isLoadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200 &&
        !isLoadingMore &&
        hasMore) {
      _loadInboxs();
    }
  }

  void _toggleSelection(InboxModel item){
    setState(() {
      _selectionMode = true;
      if(_selectedIds.contains(item.id)){
        _selectedIds.remove(item.id);
        if(_selectedIds.isEmpty) _selectionMode = false;
      }else{
        _selectedIds.add(item.id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  Future<void> _markAllAsRead() async {
    try {
      await inboxApi.markAllActivitiesAsRead();

      setState(() {
        inboxs = inboxs.map((i) {
          return InboxModel(
            id: i.id,
            type: i.type,
            actor: i.actor,
            recipient: i.recipient,
            createdAt: i.createdAt,
            isRead: true,
            postId: i.postId,
            commentId: i.commentId,
            friendRequestId: i.friendRequestId,
            groupId: i.groupId,
            extraData: i.extraData,
          );
        }).toList();
      });
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    try {
      await inboxApi.deleteSelectedActivities(_selectedIds.toList());

      setState(() {
        inboxs.removeWhere((i) => _selectedIds.contains(i.id));
        _clearSelection();
      });
    } catch (e) {
      _showError(e);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<InboxModel> getFilteredInbox(int tabIndex) {
    switch (tabIndex) {
      case 1:
        return inboxs.where((item) => !item.isRead).toList();
      case 2:
        return inboxs.where((item) => item.isRead).toList();
      case 0:
      default:
        return inboxs;
    }
  }

  Future<void> _acceptActivity(InboxModel item) async {
    try {

      bool success = false;

      if (item.type == 'friend_request' && item.friendRequestId != null) {
        await inboxApi.acceptFriendRequest(item.actor.id);
        success = true;
      } else if (item.type == 'group_invite' && item.groupId != null) {
        await inboxApi.acceptGroupInvite(item.groupId!);
        success = true;
      }

      if (success) {
        await inboxApi.deleteActivityById(item.id);

        setState(() {
          inboxs.removeWhere((i) => i.id == item.id);
        });

        showTopSnackBar(context, 'Accepted successfully!', backgroundColor: Colors.green);
      }
    } catch (e) {
      showTopSnackBar(context, 'Failed to accept: $e', backgroundColor: Colors.red);
    }
  }

  Widget _buildInboxList(List<InboxModel> items) {
    if (items.isEmpty) {
      return const Center(
        child: Text('No messages here', style: TextStyle(fontSize: 18)),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      itemCount: items.length + (isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final item = items[index];

        bool showAcceptButton = item.type == 'friend_request' || item.type == 'group_invite';

        return ListTile(
          leading: _selectionMode
              ? Checkbox(
            value: _selectedIds.contains(item.id),
            onChanged: (value) {
              _toggleSelection(item);
            },
          )
              : CircleAvatar(
            backgroundImage: item.actor.avatarUrl != null
                ? NetworkImage(item.actor.avatarUrl!)
                : null,
            child: item.actor.avatarUrl == null
                ? Text(item.actor.username[0])
                : null,
          ),
          title: Text(item.actor.username),
          subtitle: Text(item.extraData),
          trailing: item.type == 'friend_request' || item.type == 'group_invite'
              ? ElevatedButton(
            onPressed: () {
              _acceptActivity(item);
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('Accept'),
          )
              : (item.isRead
              ? const Icon(Icons.mark_email_read, color: Colors.green)
              : const Icon(Icons.mark_email_unread, color: Colors.red)),
          onLongPress: () {
            _toggleSelection(item);
          },
          onTap: () {
            if (_selectionMode) {
              _toggleSelection(item);
            }
          },
        );
      },
    );
  }

  void _showError(Object e) {
    showTopSnackBar(context, 'Error: $e', backgroundColor: Colors.red,);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode ? '${_selectedIds.length} selected' : 'Inbox',
        ),
        leading: _selectionMode
            ? IconButton(
          icon: const Icon(Icons.close),
          onPressed: _clearSelection,
        )
            : null,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'mark_all_read':
                  _markAllAsRead();
                  break;
                case 'delete_selected':
                  _deleteSelected();
                  break;

              }
            },
            itemBuilder: (context) {
              if (_selectionMode) {
                return [
                  const PopupMenuItem(
                    value: 'delete_selected',
                    child: Text('Delete Selected'),
                  ),
                ];
              } else {
                return [
                  const PopupMenuItem(
                    value: 'mark_all_read',
                    child: Text('Mark All as Read'),
                  ),
                ];
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Unread'),
            Tab(text: 'Read'),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : TabBarView(
        controller: _tabController,
        children: List.generate(
          3,
              (index) => _buildInboxList(getFilteredInbox(index)),
        ),
      ),
    );
  }
}
