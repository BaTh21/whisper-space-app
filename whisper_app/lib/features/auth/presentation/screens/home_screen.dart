import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:whisper_space_flutter/core/constants/api_constants.dart';
import 'package:whisper_space_flutter/core/providers/theme_provider.dart';
import 'package:whisper_space_flutter/features/auth/data/models/diary_model.dart';
import 'package:whisper_space_flutter/features/auth/data/models/user_model.dart';
import 'package:whisper_space_flutter/features/chat/chat_screen.dart';
import 'package:whisper_space_flutter/features/feed/presentation/screens/create_diary_screen.dart';
import 'package:whisper_space_flutter/features/feed/presentation/screens/edit_diary_full_screen.dart';
import 'package:whisper_space_flutter/features/friend/presentation/screens/friend_screen.dart';
import 'package:whisper_space_flutter/shared/widgets/diary_card.dart';

import '../../../../features/feed/data/datasources/feed_api_service.dart';
import '../../../../features/feed/presentation/providers/feed_provider.dart';
import 'login_screen.dart';
import 'providers/auth_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int? _currentUserId;

  final List<Widget> _screens = [
    const FeedTab(),
    const MessagesTab(),
    const FriendsTab(),
    const NotesTab(),
    const ProfileTab(),
  ];

  final List<String> _appBarTitles = [
    'Whisper Space',
    'Messages',
    'Friends',
    'Notes',
    'Profile',
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
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

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_appBarTitles[_selectedIndex]),
            centerTitle: true,
            elevation: 0,
            actions: [
              // Theme toggle button - ALWAYS VISIBLE
              IconButton(
                icon: Icon(
                  themeProvider.isDarkMode
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  color: Theme.of(context).iconTheme.color,
                ),
                onPressed: () {
                  themeProvider.toggleTheme(!themeProvider.isDarkMode);
                },
                tooltip: themeProvider.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
              ),
              // Other action buttons based on selected tab
              if (_selectedIndex == 0) // Feed tab
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Create New Diary',
                  onPressed: () => _createNewDiaryFromHome(context),
                ),
              if (_selectedIndex == 4) // Profile tab
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: _showLogoutDialog,
                ),
            ],
          ),
          body: IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
          bottomNavigationBar: _buildBottomNavBar(),
          floatingActionButton:
              _selectedIndex == 0 ? _buildFloatingActionButton(context) : null,
        );
      },
    );
  }

  Widget _buildFloatingActionButton(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => _createNewDiaryFromHome(context),
      child: const Icon(Icons.add),
      heroTag: 'home_fab',
    );
  }

  void _createNewDiaryFromHome(BuildContext context) {
    final feedProvider = Provider.of<FeedProvider>(context, listen: false);
    final feedApiService = Provider.of<FeedApiService>(context, listen: false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateDiaryScreen(
          feedApiService: feedApiService,
          onDiaryCreated: (DiaryModel diary) {
            feedProvider.diaries.insert(0, diary);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Created: "${diary.title}"'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Feed',
        ),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: 'Messages',
        ),
        NavigationDestination(
          icon: Icon(Icons.group_outlined),
          selectedIcon: Icon(Icons.group),
          label: 'Friends',
        ),
        NavigationDestination(
          icon: Icon(Icons.note_outlined),
          selectedIcon: Icon(Icons.note),
          label: 'Notes',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outlined),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }

  Future<void> _showLogoutDialog() async {
    final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child:
                    const Text('Logout', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldLogout && mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.logout();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
        );
      }
    }
  }
}

// ============ FEED TAB ============
class FeedTab extends StatefulWidget {
  const FeedTab({super.key});

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  final ScrollController _scrollController = ScrollController();
  bool _isInitialized = false;
  bool _showCreateButton = true;
  int? _currentUserId;
  List<Group> _availableGroups = [];

  @override
  void initState() {
    super.initState();
    _initialize();
    _scrollController.addListener(_onScroll);
    _loadCurrentUser();
    _loadUserGroups();

    // ── IMPORTANT: Start real-time WebSocket listening here ─────────────────
    final feedProvider = Provider.of<FeedProvider>(context, listen: false);
    feedProvider.initializeRealTime(); // Connects WS + starts listening for new diaries
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

  Future<void> _loadUserGroups() async {
    try {
      final feedApiService =
          Provider.of<FeedApiService>(context, listen: false);
      final groups = await feedApiService.getUserGroups();
      if (mounted) {
        setState(() {
          _availableGroups = groups;
        });
      }
    } catch (e) {
      debugPrint('Failed to load groups: $e');
    }
  }

  Future<void> _initialize() async {
    await Future.delayed(const Duration(milliseconds: 100));
    final feedProvider = Provider.of<FeedProvider>(context, listen: false);
    await feedProvider.loadInitialFeed();
    if (mounted) {
      setState(() => _isInitialized = true);
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FeedProvider>(
      builder: (context, feedProvider, child) {
        if (!_isInitialized ||
            feedProvider.isLoading && feedProvider.diaries.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (feedProvider.error != null && feedProvider.diaries.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    feedProvider.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => feedProvider.refreshFeed(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: () => feedProvider.refreshFeed(),
              child: feedProvider.diaries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.feed, size: 64, color: Colors.grey),
                          const SizedBox(height: 20),
                          const Text(
                            'No diaries yet',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Be the first to share something!',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: () =>
                                _navigateToCreateDiary(feedProvider),
                            child: const Text('Create First Diary'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: feedProvider.diaries.length,
                      itemBuilder: (context, index) {
                        final diary = feedProvider.diaries[index];
                        final isOwner = diary.author.id == _currentUserId;

                        return DiaryCard(
                          diary: diary,
                          onLike: () => _handleLike(feedProvider, diary.id),
                          onFavorite: () =>
                              _handleFavorite(feedProvider, diary.id, isOwner),
                          onComment: (diaryId, content, parentId,
                                  replyToUserId) =>
                              _handleComment(feedProvider, diaryId, content,
                                  parentId, replyToUserId),
                          onEdit: (diaryToEdit) => _handleEditDiary(
                              context, feedProvider, diaryToEdit),
                          onDelete: (diaryId) => _handleDeleteDiary(
                              context, feedProvider, diaryId),
                          isOwner: isOwner,
                        );
                      },
                    ),
            ),

            if (_showCreateButton && feedProvider.diaries.isNotEmpty)
              Positioned(
                bottom: 80,
                right: 16,
                left: 16,
                child: _buildBottomCreateButton(context, feedProvider),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBottomCreateButton(
      BuildContext context, FeedProvider feedProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
      ),
    );
  }

  // ============ EVENT HANDLERS ============

  void _handleLike(FeedProvider feedProvider, int diaryId) async {
    try {
      await feedProvider.likeDiary(diaryId);
    } catch (e) {
      _showErrorSnackBar('Failed to like diary: $e');
    }
  }

  void _handleFavorite(
      FeedProvider feedProvider, int diaryId, bool isOwner) async {
    try {
      final diary = feedProvider.diaries.firstWhere((d) => d.id == diaryId);
      final isCurrentlyFavorited =
          diary.favoritedUserIds.contains(_currentUserId);

      if (isCurrentlyFavorited) {
        await feedProvider.removeFromFavorites(diaryId);
        _showSuccessSnackBar('Removed from favorites');
      } else {
        await feedProvider.saveToFavorites(diaryId);
        _showSuccessSnackBar('Added to favorites');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to update favorites: $e');
    }
  }

  void _handleComment(FeedProvider feedProvider, int diaryId, String content,
      int? parentId, int? replyToUserId) async {
    try {
      await feedProvider.createComment(
        diaryId: diaryId,
        content: content,
        parentId: parentId,
        replyToUserId: replyToUserId,
      );
      _showSuccessSnackBar('Comment posted!');
    } catch (e) {
      _showErrorSnackBar('Failed to post comment: $e');
    }
  }

  void _handleEditDiary(
      BuildContext context, FeedProvider provider, DiaryModel diary) async {
    final result = await Navigator.push<DiaryModel?>(
      context,
      MaterialPageRoute<DiaryModel?>(
        builder: (context) => EditDiaryFullScreen(
          diary: diary,
          onUpdate: (updatedDiary) async {
            try {
              final result = await provider.updateDiary(
                diaryId: updatedDiary.id,
                title: updatedDiary.title,
                content: updatedDiary.content,
                shareType: updatedDiary.shareType,
                groupIds: updatedDiary.groups.map((g) => g.id).toList(),
                imageUrls: updatedDiary.images,
                videoUrls: updatedDiary.videos,
              );

              return result;
            } catch (e) {
              rethrow;
            }
          },
          availableGroups: _availableGroups,
        ),
      ),
    );

    if (result != null && mounted) {
      _showSuccessSnackBar('Diary updated successfully!');
    }
  }

  void _handleDeleteDiary(
      BuildContext context, FeedProvider feedProvider, int diaryId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Diary'),
        content: const Text('Are you sure you want to delete this diary? '
            'This action cannot be undone.'),
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
        await feedProvider.deleteDiary(diaryId);
        _showSuccessSnackBar('Diary deleted successfully');
      } catch (e) {
        _showErrorSnackBar('Failed to delete diary: $e');
      }
    }
  }

  void _navigateToCreateDiary(FeedProvider feedProvider) {
    final feedApiService = Provider.of<FeedApiService>(context, listen: false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateDiaryScreen(
          feedApiService: feedApiService,
          onDiaryCreated: (DiaryModel diary) {
            feedProvider.diaries.insert(0, diary);

            _showSuccessSnackBar('Created: "${diary.title}"');

            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          },
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
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

class MessagesTab extends StatelessWidget {
  const MessagesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const ChatScreen();
  }
}

class FriendsTab extends StatelessWidget {
  const FriendsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const FriendScreen();
  }
}

class NotesTab extends StatelessWidget {
  const NotesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.note, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Notes',
            style: TextStyle(fontSize: 24, color: Colors.grey),
          ),
          Text('Coming soon...'),
        ],
      ),
    );
  }
}

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _isUploading = false;
  bool _isEditingUsername = false;
  late TextEditingController _usernameController;
  final GlobalKey<FormState> _usernameFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _usernameController = TextEditingController(text: authProvider.currentUser?.username ?? '');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshUserData();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _refreshUserData() async {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.getCurrentUser();
    if (authProvider.currentUser != null) {
      _usernameController.text = authProvider.currentUser!.username;
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);

        final fileSize = await file.length();
        if (fileSize > 2 * 1024 * 1024) {
          _showSnackBar('Image too large. Maximum size is 2MB.', true);
          return;
        }

        setState(() {
          _isUploading = true;
        });

        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final success = await authProvider.uploadAvatar(file);

        if (success) {
          await _refreshUserData();
          _showSnackBar('Avatar updated successfully!', false);
        } else {
          _showSnackBar('Failed to upload avatar', true);
        }
      }
    } catch (e) {
      _showSnackBar('Error: $e', true);
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _deleteAvatar() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Avatar'),
        content: const Text('Are you sure you want to remove your avatar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await authProvider.deleteAvatar();
              if (success) {
                await _refreshUserData();
                _showSnackBar('Avatar removed successfully!', false);
              } else {
                _showSnackBar('Failed to remove avatar', true);
              }
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateUsername() async {
    if (!_usernameFormKey.currentState!.validate()) return;

    final newUsername = _usernameController.text.trim();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) {
      _showSnackBar('Please login first', true);
      return;
    }

    if (newUsername == currentUser.username) {
      setState(() => _isEditingUsername = false);
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final dio = Dio();
      final token = authProvider.storageService.getToken();

      final response = await dio.put(
        '${ApiConstants.baseUrl}/api/v1/users/me',
        data: {'username': newUsername},
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );

      if (mounted) {
        Navigator.pop(context);
      }

      if (response.statusCode == 200) {
        setState(() => _isEditingUsername = false);
        await _refreshUserData();
        _showSnackBar('Username updated successfully!', false);
      } else {
        _showSnackBar('Failed to update username', true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      _showSnackBar('Error: $e', true);
    }
  }

  void _showSnackBar(String message, bool isError) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withAlpha(26),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(title),
      trailing: Icon(
        Icons.chevron_right,
        color: Theme.of(context).textTheme.bodySmall?.color,
      ),
      onTap: onTap,
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required ThemeProvider themeProvider,
    required IconData icon,
    required String title,
    required String subtitle,
    required ThemeMode value,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () {
        themeProvider.setThemeMode(value);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withAlpha(26)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary.withAlpha(77),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).iconTheme.color?.withAlpha(153),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(179),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, ThemeProvider>(
      builder: (context, authProvider, themeProvider, child) {
        final user = authProvider.currentUser;

        if (user == null) {
          return _buildLoadingProfile();
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 8),

              // Theme Settings Card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).dividerColor.withAlpha(26),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      // Theme Toggle
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withAlpha(26),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            themeProvider.isDarkMode
                                ? Icons.dark_mode
                                : Icons.light_mode,
                            color: Theme.of(context).colorScheme.primary,
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Theme',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          themeProvider.isDarkMode ? 'Dark Mode' : 'Light Mode',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                        trailing: Switch(
                          value: themeProvider.isDarkMode,
                          onChanged: (value) {
                            themeProvider.toggleTheme(value);
                          },
                          activeThumbColor: Theme.of(context).colorScheme.primary,
                          activeTrackColor: Theme.of(context).colorScheme.primaryContainer,
                          inactiveThumbColor: Theme.of(context).colorScheme.onSurface.withAlpha(77),
                          inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      ),

                      // Theme Mode Options
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          children: [
                            _buildThemeOption(
                              context: context,
                              themeProvider: themeProvider,
                              icon: Icons.brightness_auto_rounded,
                              title: 'System Default',
                              subtitle: 'Follow device settings',
                              value: ThemeMode.system,
                              isSelected: themeProvider.themeMode == ThemeMode.system,
                            ),
                            _buildThemeOption(
                              context: context,
                              themeProvider: themeProvider,
                              icon: Icons.light_mode_rounded,
                              title: 'Light Mode',
                              subtitle: 'Always light appearance',
                              value: ThemeMode.light,
                              isSelected: themeProvider.themeMode == ThemeMode.light,
                            ),
                            _buildThemeOption(
                              context: context,
                              themeProvider: themeProvider,
                              icon: Icons.dark_mode_rounded,
                              title: 'Dark Mode',
                              subtitle: 'Always dark appearance',
                              value: ThemeMode.dark,
                              isSelected: themeProvider.themeMode == ThemeMode.dark,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Profile Header Card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).dividerColor.withAlpha(26),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Avatar with upload
                      Stack(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3,
                              ),
                            ),
                            child: ClipOval(
                              child: _buildAvatar(user),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _pickAndUploadAvatar,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(context).scaffoldBackgroundColor,
                                    width: 3,
                                  ),
                                ),
                                child: _isUploading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.camera_alt,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Username
                      _isEditingUsername
                          ? _buildUsernameEditForm(context, user, authProvider)
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  user.username,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(
                                    Icons.edit,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isEditingUsername = true;
                                    });
                                  },
                                ),
                              ],
                            ),

                      // Email
                      Text(
                        user.email,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),

                      // Verification Badge
                      if (user.isVerified)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withAlpha(26),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified,
                                size: 14,
                                color: const Color(0xFF10B981),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Verified',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Avatar Actions
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickAndUploadAvatar,
                            icon: Icon(
                              Icons.edit,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            label: Text(
                              'Change Avatar',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(26),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _deleteAvatar,
                              icon: Icon(
                                Icons.delete,
                                size: 20,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              label: Text(
                                'Remove',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.error.withAlpha(26),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Account Info Card
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).dividerColor.withAlpha(26),
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withAlpha(26),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.calendar_today,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: const Text('Member Since'),
                      subtitle: Text(
                        '${user.createdAt.day}/${user.createdAt.month}/${user.createdAt.year}',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                    Divider(
                      height: 0,
                      color: Theme.of(context).dividerColor.withAlpha(26),
                      indent: 20,
                      endIndent: 20,
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withAlpha(26),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.update,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: const Text('Last Updated'),
                      subtitle: Text(
                        '${user.updatedAt.day}/${user.updatedAt.month}/${user.updatedAt.year}',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Settings Menu
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).dividerColor.withAlpha(26),
                  ),
                ),
                child: Column(
                  children: [
                    _buildMenuItem(
                      Icons.settings_outlined,
                      'Settings',
                      () {},
                    ),
                    Divider(
                      height: 0,
                      color: Theme.of(context).dividerColor.withAlpha(26),
                      indent: 20,
                      endIndent: 20,
                    ),
                    _buildMenuItem(
                      Icons.notifications_outlined,
                      'Notifications',
                      () {},
                    ),
                    Divider(
                      height: 0,
                      color: Theme.of(context).dividerColor.withAlpha(26),
                      indent: 20,
                      endIndent: 20,
                    ),
                    _buildMenuItem(
                      Icons.privacy_tip_outlined,
                      'Privacy',
                      () {},
                    ),
                    Divider(
                      height: 0,
                      color: Theme.of(context).dividerColor.withAlpha(26),
                      indent: 20,
                      endIndent: 20,
                    ),
                    _buildMenuItem(
                      Icons.help_outline,
                      'Help & Support',
                      () {},
                    ),
                  ],
                ),
              ),

              // Logout Button
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final homeState = context.findAncestorStateOfType<_HomeScreenState>();
                    homeState?._showLogoutDialog();
                  },
                  icon: Icon(
                    Icons.logout,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  label: Text(
                    'Logout',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error.withAlpha(26),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvatar(User user) {
    if (_isUploading) {
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) {
      return Image.network(
        user.avatarUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: const Color(0xFF7C3AED),
            child: const Icon(
              Icons.person,
              size: 60,
              color: Colors.white,
            ),
          );
        },
      );
    }

    return Container(
      color: const Color(0xFF7C3AED),
      child: const Icon(
        Icons.person,
        size: 60,
        color: Colors.white,
      ),
    );
  }

  Widget _buildUsernameEditForm(BuildContext context, User user, AuthProvider authProvider) {
    return Form(
      key: _usernameFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _usernameController,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              labelText: 'Username',
              hintText: 'Enter new username',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.check, color: Theme.of(context).colorScheme.primary),
                    onPressed: _updateUsername,
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Theme.of(context).colorScheme.error),
                    onPressed: () {
                      setState(() {
                        _isEditingUsername = false;
                        _usernameController.text = user.username;
                      });
                    },
                  ),
                ],
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Username cannot be empty';
              }
              if (value.trim().length < 3) {
                return 'Username must be at least 3 characters';
              }
              if (value.trim().length > 20) {
                return 'Username cannot exceed 20 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Username must be 3-20 characters',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingProfile() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Loading profile...',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }
}