// lib/features/feed/presentation/screens/feed_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import 'package:whisper_space_flutter/features/feed/presentation/screens/create_diary_screen.dart';
import 'package:whisper_space_flutter/shared/widgets/diary_card.dart';

import '../../data/datasources/feed_api_service.dart';
import '../providers/feed_provider.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  bool _showCreateButton = true;
  bool _showNewDiaryNotificationBanner = false;
  DiaryModel? _latestNewDiary;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadCurrentUser();
  }

  void _loadCurrentUser() {
    // TODO: Load current user ID from your AuthProvider
    // Replace this with your actual user ID retrieval
    // Example:
    // final authProvider = Provider.of<AuthProvider>(context, listen: false);
    // _currentUserId = authProvider.currentUser?.id;
    _currentUserId = 1; // Temporary - replace with actual user ID
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final provider = Provider.of<FeedProvider>(context, listen: false);
      provider.reconnectWebSocket();
    }
  }

  void _onScroll() {
    final currentScroll = _scrollController.position.pixels;
    
    if (currentScroll > 100 && _showCreateButton) {
      setState(() => _showCreateButton = false);
    } else if (currentScroll <= 100 && !_showCreateButton) {
      setState(() => _showCreateButton = true);
    }
  }

  void _showNotificationForNewDiary(DiaryModel diary) {
    if (mounted) {
      setState(() {
        _showNewDiaryNotificationBanner = true;
        _latestNewDiary = diary;
      });

      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _showNewDiaryNotificationBanner = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FeedProvider>(
      builder: (context, provider, child) {
        // Set current user ID in provider
        if (_currentUserId != null) {
          // FeedProvider should have a method to set current user ID
          // If not, you need to add it to FeedProvider
        }

        if (provider.isLoading && provider.diaries.isEmpty) {
          return _buildLoadingScreen(provider);
        }

        if (provider.error != null && provider.diaries.isEmpty) {
          return _buildErrorScreen(provider);
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Text('Whisper Space'),
                const SizedBox(width: 8),
                _buildWebSocketIndicator(provider),
              ],
            ),
            elevation: 0,
            actions: [
              if (!provider.isWsConnected && !provider.isWsConnecting)
                IconButton(
                  icon: const Icon(Icons.wifi_off, color: Colors.orange),
                  tooltip: 'Reconnect to real-time updates',
                  onPressed: () => provider.reconnectWebSocket(),
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh feed',
                onPressed: () => provider.refreshFeed(),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Create New Diary',
                onPressed: () => _createNewPost(context, provider),
              ),
            ],
          ),
          body: Stack(
            children: [
              RefreshIndicator(
                onRefresh: () => provider.refreshFeed(),
                child: _buildFeedContent(provider),
              ),
              
              if (_showNewDiaryNotificationBanner && _latestNewDiary != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  right: 16,
                  child: _buildNewDiaryNotification(_latestNewDiary!),
                ),
              
              if (_showCreateButton && provider.diaries.isNotEmpty)
                Positioned(
                  bottom: 16,
                  right: 16,
                  left: 16,
                  child: _buildBottomCreateButton(context, provider),
                ),
            ],
          ),
          floatingActionButton: _buildFloatingActionButton(context, provider),
          
          bottomNavigationBar: _buildBottomNavigationBar(context, provider),
        );
      },
    );
  }

  Widget _buildWebSocketIndicator(FeedProvider provider) {
    Color color;
    IconData icon;
    String tooltip;
    
    if (provider.isWsConnected) {
      color = Colors.green;
      icon = Icons.wifi;
      tooltip = 'Real-time updates connected';
    } else if (provider.isWsConnecting) {
      color = Colors.orange;
      icon = Icons.wifi_find;
      tooltip = 'Connecting to real-time updates...';
    } else {
      color = Colors.red;
      icon = Icons.wifi_off;
      tooltip = 'Real-time updates disconnected';
    }
    
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
        child: Icon(icon, size: 10, color: Colors.white),
      ),
    );
  }

  Widget _buildLoadingScreen(FeedProvider provider) {
    return Scaffold(
      appBar: AppBar(title: const Text('Whisper Space')),
      body: const Center(child: CircularProgressIndicator()),
      floatingActionButton: _buildFloatingActionButton(context, provider),
    );
  }

  Widget _buildErrorScreen(FeedProvider provider) {
    return Scaffold(
      appBar: AppBar(title: const Text('Whisper Space')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                provider.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => provider.refreshFeed(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(context, provider),
    );
  }

  Widget _buildFeedContent(FeedProvider provider) {
    if (provider.diaries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.feed, size: 64, color: Colors.grey),
            const SizedBox(height: 20),
            const Text(
              'No posts yet',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            const Text(
              'Be the first to share something!',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _createNewPost(context, provider),
              child: const Text('Create First Diary'),
            ),
            const SizedBox(height: 20),
            _buildWebSocketStatusText(provider),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: provider.diaries.length,
      itemBuilder: (context, index) {
        final diary = provider.diaries[index];
        final isOwner = diary.author.id == _currentUserId;
        
        return DiaryCard(
          diary: diary,
          onLike: () => _handleLike(provider, diary.id),
          onFavorite: () => _handleFavorite(provider, diary.id, isOwner),
          onComment: (diaryId, content) => _handleComment(
            provider, 
            diaryId, 
            content
          ),
          onEdit: (diaryToEdit) => _handleEditDiary(
            context, 
            provider, 
            diaryToEdit
          ),
          onDelete: (diaryId) => _handleDeleteDiary(
            context, 
            provider, 
            diaryId
          ),
          isOwner: isOwner,
        );
      },
    );
  }

  Widget _buildWebSocketStatusText(FeedProvider provider) {
    String text;
    Color color;
    
    if (provider.isWsConnected) {
      text = '✅ Real-time updates active';
      color = Colors.green;
    } else if (provider.isWsConnecting) {
      text = '🔄 Connecting to real-time updates...';
      color = Colors.orange;
    } else {
      text = '⚠️ Real-time updates inactive';
      color = Colors.orange;
    }
    
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12,
      ),
    );
  }

  Widget _buildNewDiaryNotification(DiaryModel diary) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundImage: diary.author.avatarUrl != null && 
                  diary.author.avatarUrl!.isNotEmpty
                  ? NetworkImage(diary.author.avatarUrl!)
                  : null,
              radius: 20,
              child: diary.author.avatarUrl == null || 
                  diary.author.avatarUrl!.isEmpty
                  ? Text(diary.author.username.isNotEmpty ? 
                      diary.author.username[0] : '?')
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📝 New diary from ${diary.author.username}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (diary.title.isNotEmpty)
                    Text(
                      diary.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12, 
                        color: Colors.grey
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                setState(() {
                  _showNewDiaryNotificationBanner = false;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton(BuildContext context, FeedProvider provider) {
    return FloatingActionButton(
      onPressed: () => _createNewPost(context, provider),
      tooltip: 'Create New Diary',
      child: const Icon(Icons.add),
    );
  }

  Widget _buildBottomCreateButton(BuildContext context, FeedProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _createNewPost(context, provider),
          borderRadius: BorderRadius.circular(30),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.add_circle_outline, color: Colors.white),
                const SizedBox(width: 12),
                const Text(
                  'Create Diary',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Badge(
                  backgroundColor: Colors.red,
                  label: Text('${provider.diaries.length}'),
                  child: const Icon(
                    Icons.article_outlined, 
                    color: Colors.white
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context, FeedProvider provider) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: IconButton(
              icon: const Icon(Icons.home, size: 28),
              onPressed: () {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              tooltip: 'Home',
            ),
          ),
          
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(8),
              child: ElevatedButton.icon(
                onPressed: () => _createNewPost(context, provider),
                icon: const Icon(Icons.add_circle, size: 24),
                label: const Text(
                  'CREATE',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 4,
                ),
              ),
            ),
          ),
          
          Expanded(
            child: IconButton(
              icon: const Icon(Icons.person, size: 28),
              onPressed: _navigateToProfile,
              tooltip: 'Profile',
            ),
          ),
        ],
      ),
    );
  }

  // ============ EVENT HANDLERS ============

  void _handleLike(FeedProvider provider, int diaryId) async {
    try {
      await provider.likeDiary(diaryId);
    } catch (e) {
      _showErrorSnackBar('Failed to like diary: $e');
    }
  }

  void _handleFavorite(FeedProvider provider, int diaryId, bool isOwner) async {
    try {
      // Check if already favorited
      final diary = provider.diaries.firstWhere((d) => d.id == diaryId);
      final isCurrentlyFavorited = diary.favoritedUserIds.contains(_currentUserId);

      if (isCurrentlyFavorited) {
        await provider.removeFromFavorites(diaryId);
      } else {
        await provider.saveToFavorites(diaryId);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to update favorites: $e');
    }
  }

  void _handleComment(
    FeedProvider provider, 
    int diaryId, 
    String content
  ) async {
    try {
      await provider.createComment(
        diaryId: diaryId,
        content: content,
      );
    } catch (e) {
      _showErrorSnackBar('Failed to post comment: $e');
    }
  }

  void _handleEditDiary(
    BuildContext context,
    FeedProvider provider,
    DiaryModel diary
  ) async {
    // Create a simple edit dialog since we don't have EditDiaryScreen yet
    final result = await _showEditDialog(context, diary);
    
    if (result != null && result.isNotEmpty) {
      try {
        await provider.updateDiary(
          diaryId: diary.id,
          content: result,
          title: diary.title, // Keep existing title
          shareType: diary.shareType,
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Diary updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        _showErrorSnackBar('Failed to update diary: $e');
      }
    }
  }

  Future<String?> _showEditDialog(BuildContext context, DiaryModel diary) async {
    final controller = TextEditingController(text: diary.content);
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Diary'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Edit your diary content...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _handleDeleteDiary(
    BuildContext context,
    FeedProvider provider,
    int diaryId
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Diary'),
        content: const Text(
          'Are you sure you want to delete this diary? '
          'This action cannot be undone.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await provider.deleteDiary(diaryId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Diary deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar('Failed to delete diary: $e');
        }
      }
    }
  }

  void _createNewPost(BuildContext context, FeedProvider provider) {
    final feedApiService = Provider.of<FeedApiService>(context, listen: false);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateDiaryScreen(
          feedApiService: feedApiService,
          onDiaryCreated: (DiaryModel diary) {
            provider.diaries.insert(0, diary);
            // Only add to myDiaries if it's the current user's diary
            if (diary.author.id == _currentUserId) {
              provider.myDiaries.insert(0, diary);
            }
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Diary created successfully!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
            
            _showNotificationForNewDiary(diary);
          },
        ),
      ),
    );
  }

  void _navigateToProfile() {
    // TODO: Implement profile navigation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile page coming soon!')),
    );
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}