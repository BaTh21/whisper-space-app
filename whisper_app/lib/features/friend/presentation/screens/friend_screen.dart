import 'package:flutter/material.dart';
import 'package:whisper_space_flutter/core/services/storage_service.dart';
import '../datasources/friend_api_source.dart';
import 'package:whisper_space_flutter/utils/snack_bar.dart';

enum _FriendAction {
  viewProfile,
  chat,
  cancel,
  accept,
  block,
  unblock,
}

enum FriendStatus {
  friend,
  pending,
  requesting,
  blocked,
}

FriendStatus parseStatus(String status) {
  switch (status.toLowerCase()) {
    case 'friend':
    case 'accepted':
      return FriendStatus.friend;
    case 'pending':
      return FriendStatus.pending;
    case 'request':
    case 'requesting':
      return FriendStatus.requesting;
    case 'blocked':
      return FriendStatus.blocked;
    default:
      return FriendStatus.friend;
  }
}

class FriendBox extends StatelessWidget {
  final String name;
  final String? avatarUrl; // allow null
  final FriendStatus status;
  final Widget? trailing;

  final VoidCallback? onViewProfile;
  final VoidCallback? onOpenChat;
  final VoidCallback? onCancel;
  final VoidCallback? onAccept;
  final VoidCallback? onBlock;
  final VoidCallback? onUnblock;

  const FriendBox({
    super.key,
    required this.name,
    this.avatarUrl,
    required this.status,
    this.trailing,
    this.onViewProfile,
    this.onOpenChat,
    this.onCancel,
    this.onAccept,
    this.onBlock,
    this.onUnblock
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: PopupMenuButton<_FriendAction>(
        position: PopupMenuPosition.under,
        offset: const Offset(200, 0),
        onSelected: (action) {
          switch (action) {
            case _FriendAction.viewProfile:
              onViewProfile?.call();
              break;
            case _FriendAction.chat:
              onOpenChat?.call();
              break;
            case _FriendAction.cancel:
              onCancel?.call();
              break;
            case _FriendAction.accept:
              onAccept?.call();
              break;
            case _FriendAction.block:
              onBlock?.call();
              break;
            case _FriendAction.unblock:
              onUnblock?.call();
              break;
          }
        },
        itemBuilder: (context) => _buildMenuItems(status),
        child: ListTile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: Colors.blueGrey,
            backgroundImage:
            avatarUrl != null && avatarUrl!.isNotEmpty
                ? NetworkImage(avatarUrl!)
                : null,
            child: avatarUrl != null && avatarUrl!.isNotEmpty
                ? null
                : Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(_statusLabel(status)),
          trailing: const Icon(Icons.more_vert),
        ),
      ),
    );
  }

  static String _statusLabel(FriendStatus status) {
    switch (status) {
      case FriendStatus.friend:
        return 'Friend';
      case FriendStatus.pending:
        return 'Pending';
      case FriendStatus.requesting:
        return 'Request';
      case FriendStatus.blocked:
        return 'Blocked';
    }
  }

  static List<PopupMenuEntry<_FriendAction>> _buildMenuItems(
      FriendStatus status,
      ) {
    switch (status) {
      case FriendStatus.friend:
        return const [
          PopupMenuItem(
            value: _FriendAction.viewProfile,
            child: Text('View Profile'),
          ),
          PopupMenuItem(
            value: _FriendAction.chat,
            child: Text('Open Chat'),
          ),
          PopupMenuItem(
            value: _FriendAction.block,
            child: Text('Block'),
          ),
        ];

      case FriendStatus.pending:
        return const [
          PopupMenuItem(
            value: _FriendAction.cancel,
            child: Text('Cancel Request'),
          ),
        ];

      case FriendStatus.requesting:
        return const [
          PopupMenuItem(
            value: _FriendAction.accept,
            child: Text('Accept'),
          ),
          PopupMenuItem(
            value: _FriendAction.block,
            child: Text('Block'),
          ),
        ];

      case FriendStatus.blocked:
        return const [
          PopupMenuItem(
            value: _FriendAction.unblock,
            child: Text('Unblock'),
          ),
        ];
    }
  }
}

class SuggestFriendBox extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final VoidCallback? onAdd;

  const SuggestFriendBox({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.onAdd
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140, // Fixed width for inline box
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.blueGrey,
                backgroundImage:
                avatarUrl != null && avatarUrl!.isNotEmpty ? NetworkImage(avatarUrl!):null,
                child: avatarUrl != null && avatarUrl!.isNotEmpty
                    ? null
                    : Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.person_add, size: 16),
                label: const Text('Add', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SuggestFriendShowMoreBox extends StatelessWidget{
  const SuggestFriendShowMoreBox({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Card(
        color: Colors.grey.shade200,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: (){
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Show more'))
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              'Show More',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 16
              ),
            ),
          ),
        ),
      )
    );
  }
}

class FriendScreen extends StatefulWidget {
  const FriendScreen({super.key});

  @override
  State<FriendScreen> createState() => _FriendScreenState();
}

class _FriendScreenState extends State<FriendScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  late FriendAPISource friendApi;

  bool isLoading = true;

  List<Map<String, String>> suggestFriends = [];
  List<Map<String, String>> allFriends = [];
  List<Map<String, String>> pendingFriends = [];
  List<Map<String, String>> requestFriends = [];
  List<Map<String, String>> blockedFriends = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    friendApi = FriendAPISource(storageService: StorageService());

    initServicesAndLoad();
  }

  Future<void> initServicesAndLoad() async {
    final storageService = StorageService();
    await storageService.init();

    friendApi = FriendAPISource(storageService: storageService);

    loadFriends();
  }

  List<Map<String, String>> _mapAllFriends(List<dynamic> list){
    return list.map<Map<String, String>>((f){

      return {
        'id': f['id'].toString(),
        'name': f['username'] ?? '',
        'avatar': f['avatar_url'] ?? '',
        'status': f['status'] ?? ''
      };
    }).toList();
  }

  List<Map<String, String>> _mapPendingFriends(List<dynamic> list){
    return list.map<Map<String, String>>((f){

      return {
        'pending_id': f['id'].toString(),
        'id': f['friend']['id'].toString(),
        'name': f['friend']['username'] ?? '',
        'avatar': f['friend']['avatar_url'] ?? '',
        'status': f['status'] ?? ''
      };
    }).toList();
  }

  List<Map<String, String>> _mapRequestingFriends(List<dynamic> list){
    return list.map<Map<String, String>>((f){
      return {
        'id': f['requester_id'].toString(),
        'name': f['requester_username'] ?? '',
        'avatar': f['requester_avatar_url'] ?? '',
        'status': f['status'] ?? ''
      };
    }).toList();
  }

  List<Map<String, String>> _mapBlockedUsers(List<dynamic> list){
    return list.map<Map<String, String>>((f){
      return {
        'id': f['id'].toString(),
        'name': f['username'] ?? '',
        'avatar': f['avatar_url'] ?? '',
        'status': f['status'] ?? ''
      };
    }).toList();
  }

  List<Map<String, String>> _mapSuggestedUsers(List<dynamic> list){
    return list.map<Map<String, String>> ((f){
      return {
        'id': f['id'].toString(),
        'name': f['username'] ?? '',
        'avatar': f['avatar_url'] ?? '',
        // 'status': f['status'] ?? ''
      };
    }).toList();
  }

  Future<void> loadFriends() async {
    try{
      final pendingData = await friendApi.getPendingRequests();
      final requestingData = await friendApi.getRequestingUsers();
      final blockedData = await friendApi.getBlockedUsers();
      final suggestionData = await friendApi.getSuggestionUsers();
      final data = await friendApi.getFriends();
      if (!mounted) return;

      setState(() {
        suggestFriends = _mapSuggestedUsers(suggestionData);
        allFriends = _mapAllFriends(data);
        pendingFriends = _mapPendingFriends(pendingData);
        requestFriends = _mapRequestingFriends(requestingData);
        blockedFriends = _mapBlockedUsers(blockedData);
        isLoading = false;
      });

    }catch(e){
      debugPrint('Error loading friend: $e');
      setState(()=> isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if(suggestFriends.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Suggest Friend',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              SizedBox(
                height: 200,
                child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: suggestFriends.length + 1,
                    itemBuilder: (context, index){
                      if (index == suggestFriends.length){
                        return const SuggestFriendShowMoreBox();
                      }
                      final friend = suggestFriends[index];
                      final id = int.tryParse(friend['id'] ?? '');

                      return SuggestFriendBox(
                          name: friend['name']!,
                          avatarUrl: friend['avatar']!,
                          onAdd: id == null
                            ? () {
                            debugPrint('Invalid user id');
                          }:() async{
                            try{
                              await friendApi.sendFriendRequest(id);

                              showTopSnackBar(context, 'Friend request sent to ${friend['name']}');

                              await loadFriends();

                            }catch(e){
                              showTopSnackBar(context, e.toString());
                            }
                          },
                      );
                    }
                ),
              )],
              const SizedBox(
                height: 16
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                    'Your friends',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey, width: 0.2),
                    bottom: BorderSide(color: Colors.grey, width: 0.1),
                  ),
                  color: Colors.transparent,
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: Theme.of(context).primaryColor,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Theme.of(context).primaryColor,
                  indicatorWeight: 4,
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: const [
                    Tab(text: 'All Friends'),
                    Tab(text: 'Pending'),
                    Tab(text: 'Requests'),
                    Tab(text: 'Blocked'),
                  ],
                ),
              ),

              SizedBox(
                height: 400,
                child: TabBarView(
                  controller: _tabController,
                    children: [
                      ListView(
                        children: allFriends.map((f) {
                          return FriendBox(
                            name: f['name']!,
                            avatarUrl: f['avatar'],
                            status: FriendStatus.friend,
                            onViewProfile: () {
                              debugPrint('View profile ${f['name']}');
                            },
                            onOpenChat: () {
                              debugPrint('Open chat with ${f['name']}');
                            },
                            onBlock: () async {
                              final id = int.tryParse(f['id'] ?? '');
                              if (id == null) return;
                              await friendApi.blockUser(id);
                              await loadFriends();
                            },
                          );
                        }).toList(),
                      ),
                      ListView(
                        children: pendingFriends.map((f) {
                          return FriendBox(
                            name: f['name']!,
                            avatarUrl: f['avatar'],
                            status: FriendStatus.pending,
                            onCancel: () async {
                              final id = int.tryParse(f['pending_id'] ?? '');
                              if (id == null) return;
                              await friendApi.cancelPending(id);
                              await loadFriends();
                            },
                          );
                        }).toList(),
                      )
                      ,
                      ListView(
                        children: requestFriends.map((f) {
                          return FriendBox(
                            name: f['name']!,
                            avatarUrl: f['avatar'],
                            status: FriendStatus.requesting,
                            onAccept: () async {
                              final id = int.tryParse(f['id'] ?? '');
                              if (id == null) return;
                              await friendApi.acceptFriendRequest(id);
                              await loadFriends();
                            },
                            onBlock: () async {
                              final id = int.tryParse(f['id'] ?? '');
                              if (id == null) return;
                              await friendApi.blockUser(id);
                              await loadFriends();
                            },
                          );
                        }).toList(),
                      )
                      ,
                      ListView(
                        children: blockedFriends.map((f) {
                          return FriendBox(
                            name: f['name']!,
                            avatarUrl: f['avatar'],
                            status: FriendStatus.blocked,
                            onUnblock: () async {
                              final id = int.tryParse(f['id'] ?? '');
                              if (id == null) return;
                              await friendApi.unblockUser(id);
                              await loadFriends();
                            },
                          );
                        }).toList(),
                      )
                    ]
                ),
              )
            ],
          ),
        )


    );
  }

}
