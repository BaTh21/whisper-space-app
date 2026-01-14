// lib/shared/widgets/media_gallery.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MediaGallery extends StatefulWidget {
  final List<String> images;
  final List<String> videos;
  final List<String> videoThumbnails;
  final double height;
  final BorderRadius borderRadius;

  const MediaGallery({
    super.key,
    required this.images,
    required this.videos,
    required this.videoThumbnails,
    this.height = 250,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<MediaGallery> {
  final List<MediaItem> _allMedia = [];

  @override
  void initState() {
    super.initState();
    _prepareMedia();
  }

  void _prepareMedia() {
    _allMedia.clear();
    
    // Add images
    for (var imageUrl in widget.images) {
      if (imageUrl.isNotEmpty) {
        _allMedia.add(MediaItem(
          url: imageUrl,
          type: MediaType.image,
        ));
      }
    }
    
    // Add videos
    for (int i = 0; i < widget.videos.length; i++) {
      final videoUrl = widget.videos[i];
      if (videoUrl.isNotEmpty) {
        _allMedia.add(MediaItem(
          url: videoUrl,
          type: MediaType.video,
          thumbnail: i < widget.videoThumbnails.length 
              ? widget.videoThumbnails[i]
              : null,
        ));
      }
    }
  }

  bool _isValidImageUrl(String url) {
    if (url.isEmpty) return false;
    
    // Check if it's a video file
    final videoExtensions = ['.mp4', '.mov', '.avi', '.webm', '.mkv'];
    for (var ext in videoExtensions) {
      if (url.toLowerCase().contains(ext)) {
        return false;
      }
    }
    
    // For Cloudinary URLs, check if it's an image transformation
    if (url.contains('cloudinary.com')) {
      // Cloudinary image URLs should have proper transformations
      if (url.contains('/image/upload/')) {
        return true;
      }
      // Cloudinary video thumbnails (without .mp4 extension) are valid images
      if (url.contains('/video/upload/') && 
          !url.contains('.mp4') &&
          !url.contains('.mov') &&
          !url.contains('.avi') &&
          !url.contains('.webm')) {
        return true;
      }
    }
    
    // Check common image extensions
    final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
    for (var ext in imageExtensions) {
      if (url.toLowerCase().contains(ext)) {
        return true;
      }
    }
    
    return false;
  }

  Widget _buildThumbnail(MediaItem item, int index) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[100],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background container
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.grey[200]!,
                  Colors.grey[300]!,
                ],
              ),
            ),
          ),

          // Media content
          if (item.type == MediaType.image)
            _buildImageThumbnail(item.url)
          else if (item.thumbnail != null && 
                   item.thumbnail!.isNotEmpty && 
                   _isValidImageUrl(item.thumbnail!))
            _buildImageThumbnail(item.thumbnail!)
          else
            _buildVideoPlaceholder(),

          // Video overlay with play button
          if (item.type == MediaType.video)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.black.withOpacity(0.2),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ),

          // Media type badge
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: item.type == MediaType.video
                    ? Colors.blue[800]!.withOpacity(0.9)
                    : Colors.purple[700]!.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    item.type == MediaType.video
                        ? Icons.videocam
                        : Icons.photo,
                    size: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item.type == MediaType.video ? 'VIDEO' : 'PHOTO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageThumbnail(String imageUrl) {
    if (!_isValidImageUrl(imageUrl)) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.grey[200]!,
              Colors.grey[300]!,
            ],
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.photo,
            color: Colors.grey,
            size: 40,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.grey[200]!,
                Colors.grey[300]!,
              ],
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          ),
        ),
        errorWidget: (context, url, error) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.grey[200]!,
                  Colors.grey[300]!,
                ],
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.photo,
                color: Colors.grey,
                size: 40,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey[800]!,
            Colors.grey[900]!,
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.videocam,
          color: Colors.white,
          size: 50,
        ),
      ),
    );
  }

  void _openMediaViewer(MediaItem item, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenGalleryViewer(
          mediaItems: _allMedia,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_allMedia.isEmpty) return const SizedBox.shrink();

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
      ),
      child: _allMedia.length == 1 
          ? _buildSingleMedia(_allMedia.first, 0)
          : _buildMediaGrid(),
    );
  }

  Widget _buildSingleMedia(MediaItem item, int index) {
    return GestureDetector(
      onTap: () => _openMediaViewer(item, index),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: _buildThumbnail(item, index),
        ),
      ),
    );
  }

  Widget _buildMediaGrid() {
    final maxItems = _allMedia.length <= 2 ? 2 : 4;
    final crossAxisCount = _allMedia.length <= 2 ? 2 : 2;
    
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
              childAspectRatio: 1,
            ),
            itemCount: _allMedia.length > maxItems ? maxItems : _allMedia.length,
            itemBuilder: (context, index) {
              final item = _allMedia[index];
              final isLastItem = index == maxItems - 1 && _allMedia.length > maxItems;
              
              return GestureDetector(
                onTap: () => _openMediaViewer(item, index),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildThumbnail(item, index),
                        if (isLastItem)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.black.withOpacity(0.7),
                              ),
                              child: Center(
                                child: Text(
                                  '+${_allMedia.length - maxItems}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        
        if (_allMedia.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ElevatedButton.icon(
              onPressed: () => _openMediaViewer(_allMedia.first, 0),
              icon: const Icon(Icons.grid_view, size: 16),
              label: Text(
                'View all (${_allMedia.length})',
                style: const TextStyle(fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 36),
                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                foregroundColor: Theme.of(context).primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 0,
              ),
            ),
          ),
      ],
    );
  }
}

// Full Screen Gallery Viewer
class FullScreenGalleryViewer extends StatefulWidget {
  final List<MediaItem> mediaItems;
  final int initialIndex;

  const FullScreenGalleryViewer({
    super.key,
    required this.mediaItems,
    this.initialIndex = 0,
  });

  @override
  State<FullScreenGalleryViewer> createState() => _FullScreenGalleryViewerState();
}

class _FullScreenGalleryViewerState extends State<FullScreenGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _startHideControlsTimer();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startHideControlsTimer();
      } else {
        _hideControlsTimer?.cancel();
      }
    });
  }

  void _nextItem() {
    if (_currentIndex < widget.mediaItems.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousItem() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // PageView for media
          GestureDetector(
            onTap: _toggleControls,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.mediaItems.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
                _startHideControlsTimer();
              },
              itemBuilder: (context, index) {
                final item = widget.mediaItems[index];
                
                if (item.type == MediaType.image) {
                  return InteractiveViewer(
                    panEnabled: true,
                    scaleEnabled: true,
                    child: Center(
                      child: CachedNetworkImage(
                        imageUrl: item.url,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (context, url, error) => Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.broken_image, color: Colors.white, size: 48),
                              const SizedBox(height: 16),
                              const Text(
                                'Failed to load image',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                } else {
                  return VideoPlayerItem(
                    videoUrl: item.url,
                  );
                }
              },
            ),
          ),

          // Top controls
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_currentIndex + 1} / ${widget.mediaItems.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.mediaItems[_currentIndex].type == MediaType.video
                                ? Icons.videocam
                                : Icons.photo,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom controls
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Previous button
                        if (_currentIndex > 0)
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.chevron_left,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            onPressed: _previousItem,
                          )
                        else
                          const SizedBox(width: 60),

                        // Next button
                        if (_currentIndex < widget.mediaItems.length - 1)
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.chevron_right,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            onPressed: _nextItem,
                          )
                        else
                          const SizedBox(width: 60),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Video Player Item
class VideoPlayerItem extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;

  const VideoPlayerItem({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
  });

  @override
  State<VideoPlayerItem> createState() => _VideoPlayerItemState();
}

class _VideoPlayerItemState extends State<VideoPlayerItem> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.network(
        widget.videoUrl,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
        ),
      );

      await _videoController.initialize();
      
      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        autoPlay: true,
        looping: false,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.blue,
          handleColor: Colors.blue,
          backgroundColor: Colors.grey,
          bufferedColor: Colors.grey,
        ),
        placeholder: Container(color: Colors.black),
        autoInitialize: true,
        showControlsOnInitialize: true,
      );

      setState(() {
        _isLoading = false;
      });

    } catch (e) {
      print('Video initialization error: $e');
      
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Failed to load video',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _initializeVideo,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: _chewieController != null &&
          _chewieController!.videoPlayerController.value.isInitialized
          ? Chewie(controller: _chewieController!)
          : const Center(
              child: Text(
                'Video player not available',
                style: TextStyle(color: Colors.white),
              ),
            ),
    );
  }
}

enum MediaType { image, video }

class MediaItem {
  final String url;
  final MediaType type;
  final String? thumbnail;

  const MediaItem({
    required this.url,
    required this.type,
    this.thumbnail,
  });
}