// lib/shared/widgets/media_gallery.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class MediaGallery extends StatefulWidget {
  final List<String> images;
  final List<String> videos;
  final List<String>? videoThumbnails;
  final double height;
  final BorderRadius? borderRadius;
  final bool showCountIndicator;

  const MediaGallery({
    super.key,
    required this.images,
    required this.videos,
    this.videoThumbnails,
    this.height = 250,
    this.borderRadius,
    this.showCountIndicator = true,
  });

  @override
  State<MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<MediaGallery> {
  List<MediaItem> get _mediaItems {
    final items = <MediaItem>[];
    
    // Add images
    for (final imageUrl in widget.images) {
      items.add(MediaItem(url: imageUrl, isVideo: false));
    }
    
    // Add videos
    for (int i = 0; i < widget.videos.length; i++) {
      items.add(MediaItem(
        url: widget.videos[i],
        isVideo: true,
        thumbnailUrl: widget.videoThumbnails != null && 
                     i < widget.videoThumbnails!.length
            ? widget.videoThumbnails![i]
            : null,
      ));
    }
    
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _mediaItems;
    final totalItems = items.length;
    
    if (totalItems == 0) return const SizedBox.shrink();
    
    if (totalItems == 1) {
      return _buildSingleItem(items[0], 0);
    }
    
    if (totalItems == 2) {
      return SizedBox(
        height: widget.height,
        child: Row(
          children: [
            Expanded(child: _buildItem(items[0], 0, isFirst: true)),
            const SizedBox(width: 2),
            Expanded(child: _buildItem(items[1], 1, isLast: true)),
          ],
        ),
      );
    }
    
    if (totalItems == 3) {
      return SizedBox(
        height: widget.height,
        child: Row(
          children: [
            Expanded(
              child: _buildItem(items[0], 0, isFirst: true),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: _buildItem(items[1], 1, isFirst: true),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: _buildItem(items[2], 2, isLast: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    // 4 or more items
    return SizedBox(
      height: widget.height,
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _buildItem(items[0], 0, isFirst: true),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: _buildItem(items[1], 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _buildItem(items[2], 2),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Stack(
                    children: [
                      _buildItem(items[3], 3, isLast: true),
                      if (totalItems > 4 && widget.showCountIndicator)
                        Container(
                          color: Colors.black54,
                          child: Center(
                            child: Text(
                              '+${totalItems - 4}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleItem(MediaItem item, int index) {
    return GestureDetector(
      onTap: () => _openFullScreen([item], index),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
          child: item.isVideo
              ? _buildVideoThumbnail(item, index)
              : _buildImage(item, index),
        ),
      ),
    );
  }

  Widget _buildItem(MediaItem item, int index, {bool isFirst = false, bool isLast = false}) {
    BorderRadius borderRadius = BorderRadius.zero;
    
    if (isFirst && isLast) {
      borderRadius = widget.borderRadius ?? BorderRadius.circular(12);
    } else if (isFirst) {
      if (index == 0) {
        borderRadius = (widget.borderRadius ?? BorderRadius.circular(12)).copyWith(
          topRight: Radius.zero,
          bottomRight: Radius.zero,
          bottomLeft: Radius.zero,
        );
      } else if (index == 1) {
        borderRadius = (widget.borderRadius ?? BorderRadius.circular(12)).copyWith(
          topRight: Radius.zero,
          bottomLeft: Radius.zero,
        );
      }
    } else if (isLast) {
      if (index == 1) {
        borderRadius = (widget.borderRadius ?? BorderRadius.circular(12)).copyWith(
          topLeft: Radius.zero,
          bottomLeft: Radius.zero,
        );
      } else if (index == 2) {
        borderRadius = (widget.borderRadius ?? BorderRadius.circular(12)).copyWith(
          topLeft: Radius.zero,
          topRight: Radius.zero,
        );
      } else if (index == 3) {
        borderRadius = (widget.borderRadius ?? BorderRadius.circular(12)).copyWith(
          topLeft: Radius.zero,
        );
      }
    }
    
    return GestureDetector(
      onTap: () => _openFullScreen(_mediaItems, index),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Container(
          color: Colors.grey[200],
          child: Stack(
            fit: StackFit.expand,
            children: [
              item.isVideo
                  ? _buildVideoThumbnail(item, index)
                  : _buildImage(item, index),
              
              // Video play icon overlay
              if (item.isVideo)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail(MediaItem item, int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Thumbnail or placeholder
        if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
          Image.network(
            item.thumbnailUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[300],
                child: const Center(
                  child: Icon(
                    Icons.videocam,
                    size: 32,
                    color: Colors.grey,
                  ),
                ),
              );
            },
          )
        else
          Container(
            color: Colors.grey[300],
            child: const Center(
              child: Icon(
                Icons.videocam,
                size: 32,
                color: Colors.grey,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImage(MediaItem item, int index) {
    return Image.network(
      item.url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[200],
          child: const Center(
            child: Icon(
              Icons.broken_image,
              size: 32,
              color: Colors.grey,
            ),
          ),
        );
      },
    );
  }

  void _openFullScreen(List<MediaItem> items, int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return FullScreenGallery(
          items: items,
          initialIndex: initialIndex,
        );
      },
    );
  }
}

class FullScreenGallery extends StatefulWidget {
  final List<MediaItem> items;
  final int initialIndex;

  const FullScreenGallery({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<FullScreenGallery> {
  late PageController _pageController;
  late int _currentIndex;
  ChewieController? _chewieController;
  VideoPlayerController? _videoPlayerController;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _initializeCurrentVideo();
  }

  void _initializeCurrentVideo() async {
    final currentItem = widget.items[_currentIndex];
    if (currentItem.isVideo) {
      await _initializeVideoPlayer(currentItem.url);
    }
  }

  Future<void> _initializeVideoPlayer(String videoUrl) async {
    // Dispose previous player
    _chewieController?.dispose();
    _videoPlayerController?.dispose();

    try {
      _videoPlayerController = VideoPlayerController.network(videoUrl);
      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.red,
          handleColor: Colors.red,
          backgroundColor: Colors.grey[300]!,
          bufferedColor: Colors.grey[200]!,
        ),
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
        autoInitialize: true,
        allowFullScreen: false, // We're already full screen
        allowMuting: true,
        showControlsOnInitialize: true,
      );

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load video: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Gallery content
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              _initializeCurrentVideo();
            },
            itemBuilder: (context, index) {
              final item = widget.items[index];
              
              return Container(
                color: Colors.black,
                child: Center(
                  child: item.isVideo
                      ? (_chewieController != null && _currentIndex == index
                          ? Chewie(controller: _chewieController!)
                          : Container(
                              color: Colors.black,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ))
                      : InteractiveViewer(
                          maxScale: 4.0,
                          minScale: 1.0,
                          child: Image.network(
                            item.url,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                              );
                            },
                          ),
                        ),
                ),
              );
            },
          ),

          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),

          // Counter indicator
          if (widget.items.length > 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentIndex + 1}/${widget.items.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          // Bottom indicators for images
          if (widget.items.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.items.length,
                  (index) => GestureDetector(
                    onTap: () {
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentIndex == index
                            ? Colors.white
                            : Colors.white.withOpacity(0.5),
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

class MediaItem {
  final String url;
  final bool isVideo;
  final String? thumbnailUrl;

  MediaItem({
    required this.url,
    required this.isVideo,
    this.thumbnailUrl,
  });
}