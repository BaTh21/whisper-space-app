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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reconnect WebSocket when app resumes
      final provider = Provider.of<FeedProvider>(context, listen: false);
      provider.reconnectWebSocket();
    }
  }

  void _onScroll() {
    final currentScroll = _scrollController.position.pixels;
    
    // Show/hide create button based on scroll position
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

      // Auto-hide notification after 5 seconds
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
        // Show loading state
        if (provider.isLoading && provider.diaries.isEmpty) {
          return _buildLoadingScreen(provider);
        }

        // Show error state
        if (provider.error != null && provider.diaries.isEmpty) {
          return _buildErrorScreen(provider);
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Text('Whisper Space'),
                const SizedBox(width: 8),
                // WebSocket status indicator
                _buildWebSocketIndicator(provider),
              ],
            ),
            elevation: 0,
            actions: [
              // WebSocket reconnect button
              if (!provider.isWsConnected && !provider.isWsConnecting)
                IconButton(
                  icon: const Icon(Icons.wifi_off, color: Colors.orange),
                  tooltip: 'Reconnect to real-time updates',
                  onPressed: () => provider.reconnectWebSocket(),
                ),
              // Refresh button
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh feed',
                onPressed: () => provider.refreshFeed(),
              ),
              // Create button in app bar
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Create New Diary',
                onPressed: () => _createNewPost(context, provider),
              ),
            ],
          ),
          body: Stack(
            children: [
              // Main content
              RefreshIndicator(
                onRefresh: () => provider.refreshFeed(),
                child: _buildFeedContent(provider),
              ),
              
              // New diary notification
              if (_showNewDiaryNotificationBanner && _latestNewDiary != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  right: 16,
                  child: _buildNewDiaryNotification(_latestNewDiary!),
                ),
              
              // Fixed Create Button at bottom
              if (_showCreateButton && provider.diaries.isNotEmpty)
                Positioned(
                  bottom: 16,
                  right: 16,
                  left: 16,
                  child: _buildBottomCreateButton(context, provider),
                ),
            ],
          ),
          // Floating Action Button
          floatingActionButton: _buildFloatingActionButton(context, provider),
          
          // Bottom Navigation Bar
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
            // WebSocket status in empty state
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
        return DiaryCard(
          diary: diary,
          onLike: () => provider.likeDiary(diary.id),
          onFavorite: () => provider.saveToFavorites(diary.id),
          onComment: () => _showComments(context, diary),
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
              backgroundImage: diary.author.avatarUrl != null && diary.author.avatarUrl!.isNotEmpty
                  ? NetworkImage(diary.author.avatarUrl!)
                  : null,
              radius: 20,
              child: diary.author.avatarUrl == null || diary.author.avatarUrl!.isEmpty
                  ? Text(diary.author.username.isNotEmpty ? diary.author.username[0] : '?')
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
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                  child: const Icon(Icons.article_outlined, color: Colors.white),
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
          // Home Button
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
          
          // Create Button (Big Center Button)
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
          
          // Profile Button
          Expanded(
            child: IconButton(
              icon: const Icon(Icons.person, size: 28),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile page coming soon!')),
                );
              },
              tooltip: 'Profile',
            ),
          ),
        ],
      ),
    );
  }

  void _createNewPost(BuildContext context, FeedProvider provider) {
    final feedApiService = Provider.of<FeedApiService>(context, listen: false);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateDiaryScreen(
          feedApiService: feedApiService,
          onDiaryCreated: (DiaryModel diary) {
            // The diary will be added via WebSocket, but we can add it locally too
            provider.diaries.insert(0, diary);
            provider.myDiaries.insert(0, diary);
            
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Diary created successfully!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            
            // Auto-scroll to top
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
            
            // Show notification
            _showNotificationForNewDiary(diary);
          },
        ),
      ),
    );
  }

  void _showComments(BuildContext context, DiaryModel diary) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Comments (${diary.comments.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: diary.comments.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.comment, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No comments yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                'Be the first to comment!',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: diary.comments.length,
                          itemBuilder: (context, index) {
                            final comment = diary.comments[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: comment.user.avatarUrl != null && 
                                                comment.user.avatarUrl!.isNotEmpty
                                    ? NetworkImage(comment.user.avatarUrl!)
                                    : null,
                                child: comment.user.avatarUrl == null || 
                                       comment.user.avatarUrl!.isEmpty
                                    ? Text(comment.user.username.isNotEmpty 
                                        ? comment.user.username[0] 
                                        : '?')
                                    : null,
                              ),
                              title: Text(comment.user.username),
                              subtitle: Text(comment.content),
                              trailing: Text(
                                _formatDate(comment.createdAt),
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Add a comment...',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () {
                          // TODO: Implement comment sending
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 365) {
      return '${difference.inDays ~/ 365}y ago';
    } else if (difference.inDays > 30) {
      return '${difference.inDays ~/ 30}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}