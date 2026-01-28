import 'package:flutter/material.dart';
import 'package:whisper_space_flutter/core/services/storage_service.dart';
import './model/chat_model/chat_list_model.dart';
import './chat_api_service.dart';
import './screens/private/private_chat_screen.dart';
import './screens/group/group_chat_screen.dart';
import 'create_group_dialog.dart';

String _formatTime(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 60) {
    return "${diff.inMinutes}m";
  } else if (diff.inHours < 24) {
    return "${diff.inHours}h";
  } else {
    return "${diff.inDays}d";
  }
}

class ChatScreen extends StatefulWidget {

  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState()=> _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>{
  late final ChatAPISource chatApi;

  List<ChatListItemModel> chats = [];
  List<ChatListItemModel> filteredChats = [];
  bool isLoading = true;
  String? error;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    debugPrint('CHAT SCREEN INIT');
    initServicesAndLoad();
  }

  Future<void> initServicesAndLoad() async {
    final storageService = StorageService();
    await storageService.init();

    chatApi = ChatAPISource(storageService: storageService);

    _loadChats();
  }

  Future<void> _loadChats() async {
    try{
      final result = await chatApi.getChats();
      setState(() {
        chats = result;
        _filterChats();
        isLoading = false;
      });
    }catch(e){
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  void _filterChats(){
    if (searchQuery.isEmpty){
      filteredChats = chats;
    }else{
      filteredChats = chats
          .where((chat)=>
            chat.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();
    }
  }

  Future<void> _openCreateGroupDialog() async{
    final createdGroup = await showDialog(context: context, builder: (_)=> CreateGroupDialog(chatApi: chatApi));

    if(createdGroup != null){
      await _loadChats();
    }
  }

  Widget _buildAvatar(ChatListItemModel chat) {
    if (chat.type == 'group') {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              image: chat.avatar != null
                  ? DecorationImage(
                  image: NetworkImage(chat.avatar!), fit: BoxFit.cover)
                  : null,
              color: Colors.grey[300],
            ),
            child:
            chat.avatar == null ?
            Center(child:
            Text(chat.name[0].toUpperCase(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                // color: Colors.white,
              ),
            )
            ) : null,
          ),
          if (chat.creator != null)
            Positioned(
              bottom: -5,
              left: -5,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  color: Colors.grey[300],
                  image: chat.creator?.avatar != null
                      ? DecorationImage(
                    image: NetworkImage(chat.creator!.avatar!),
                    fit: BoxFit.cover,
                  )
                      : null,
                ),
                alignment: Alignment.center,
                child: chat.creator?.avatar == null
                    ? Text(
                  chat.creator?.username != null && chat.creator!.username!.isNotEmpty
                      ? chat.creator!.username![0].toUpperCase()
                      : "?",
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                )
                    : null,
              ),
            ),
        ],
      );
    } else {
      return SizedBox(
        width: 48,
        height: 48,
        child: CircleAvatar(
          backgroundColor: Colors.grey[300],
          child: Text(chat.name[0].toUpperCase(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              // color: Colors.white,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : RefreshIndicator(
        onRefresh: _loadChats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with Create Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'All Chats',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: 'Create Group',
                        onPressed: _openCreateGroupDialog,
                      ),
                    ],
                  ),
                ),

                // Search Bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search chats...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[200],
                    ),
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value;
                        _filterChats();
                      });
                    },
                    onSubmitted: (value) {
                      setState(() {
                        searchQuery = value;
                        _filterChats();
                      });
                    },
                  ),
                ),

                // Chat List
                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: filteredChats.length,
                  itemBuilder: (context, index) {
                    final chat = filteredChats[index];
                    return ListTile(
                      leading: _buildAvatar(chat),
                      title: Text(chat.name),
                      subtitle: Text(
                        chat.lastMessage ?? 'Tap to start new message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(_formatTime(chat.updatedAt)),
                      onTap: () {
                        if (chat.type == 'group') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupChatScreen(
                                groupId: chat.id,
                                groupName: chat.name,
                                chatApi: chatApi,
                                onRefreshChats: _loadChats,
                                storageService: chatApi.storageService,
                              ),
                            ),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PrivateChatScreen(
                                userId: chat.id,
                                userName: chat.name,
                              ),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


}