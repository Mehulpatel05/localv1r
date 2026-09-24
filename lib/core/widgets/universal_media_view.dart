import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../services/r2_storage_service.dart';

class UniversalMediaView extends StatefulWidget {
  final String? url;
  final File? file;
  final BoxFit fit;
  final bool autoPlay;
  final bool isMuted;
  final bool showControls;
  final BorderRadius? borderRadius;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const UniversalMediaView({
    super.key,
    this.url,
    this.file,
    this.fit = BoxFit.cover,
    this.autoPlay = false,
    this.isMuted = true,
    this.showControls = true,
    this.borderRadius,
    this.width,
    this.height,
    this.onTap,
  }) : assert(url != null || file != null, 'Either url or file must be provided');

  @override
  State<UniversalMediaView> createState() => _UniversalMediaViewState();
}

class _UniversalMediaViewState extends State<UniversalMediaView> {
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isPlaying = false;
  bool _isMuted = true;

  @override
  void initState() {
    super.initState();
    _isMuted = widget.isMuted;
    _checkAndInitMedia();
  }

  @override
  void didUpdateWidget(UniversalMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.file != widget.file) {
      _disposeVideoController();
      _checkAndInitMedia();
    }
  }

  void _checkAndInitMedia() {
    final path = widget.url ?? widget.file?.path ?? '';
    _isVideo = R2StorageService.isVideoFile(path);

    if (_isVideo) {
      _initVideoPlayer();
    }
  }

  Future<void> _initVideoPlayer() async {
    try {
      if (widget.url != null && widget.url!.isNotEmpty) {
        _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.url!));
      } else if (widget.file != null) {
        _videoController = VideoPlayerController.file(widget.file!);
      }

      if (_videoController == null) return;

      await _videoController!.initialize();
      _videoController!.setVolume(_isMuted ? 0.0 : 1.0);
      _videoController!.setLooping(true);

      if (widget.autoPlay) {
        await _videoController!.play();
        _isPlaying = true;
      }

      _videoController!.addListener(() {
        if (mounted && _videoController != null) {
          final isPlayingNow = _videoController!.value.isPlaying;
          if (isPlayingNow != _isPlaying) {
            setState(() => _isPlaying = isPlayingNow);
          }
        }
      });

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint('[UniversalMediaView] Video init failed: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
        });
      }
    }
  }

  void _togglePlayPause() {
    if (_videoController == null || !_isInitialized) return;
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
  }

  void _toggleMute() {
    if (_videoController == null || !_isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _videoController!.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenVideoPlayerModal(
          url: widget.url,
          file: widget.file,
          initialPosition: _videoController?.value.position,
        ),
      ),
    );
  }

  void _disposeVideoController() {
    _videoController?.dispose();
    _videoController = null;
    _isInitialized = false;
  }

  @override
  void dispose() {
    _disposeVideoController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_isVideo) {
      content = _buildVideoWidget();
    } else {
      content = _buildImageWidget();
    }

    if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: content,
    );
  }

  Widget _buildImageWidget() {
    if (widget.file != null) {
      return Image.file(
        widget.file!,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
      );
    }

    return Image.network(
      widget.url!,
      fit: widget.fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.black12,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
    );
  }

  Widget _buildVideoWidget() {
    if (_hasError) {
      return _buildErrorPlaceholder(isVideo: true);
    }

    if (!_isInitialized || _videoController == null) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.5),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap ?? _togglePlayPause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: widget.fit,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          ),

          // Play/Pause Overlay Icon
          if (!_isPlaying && widget.showControls)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
              ),
            ),

          // Video Controls Overlay
          if (widget.showControls) ...[
            // Mute Button (Top Right)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),

            // Fullscreen Button (Bottom Right)
            Positioned(
              bottom: 8,
              right: 8,
              child: GestureDetector(
                onTap: _openFullscreen,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),

            // Video Duration / Time Tag (Bottom Left)
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDuration(_videoController!.value.duration),
                  style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorPlaceholder({bool isVideo = false}) {
    return Container(
      color: const Color(0xFF1E293B),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isVideo ? Icons.videocam_off_rounded : Icons.broken_image_rounded,
              color: Colors.white54,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              isVideo ? 'Video unavailable' : 'Image unavailable',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// Standalone Fullscreen Video Player Modal
class FullscreenVideoPlayerModal extends StatefulWidget {
  final String? url;
  final File? file;
  final Duration? initialPosition;

  const FullscreenVideoPlayerModal({
    super.key,
    this.url,
    this.file,
    this.initialPosition,
  });

  @override
  State<FullscreenVideoPlayerModal> createState() => _FullscreenVideoPlayerModalState();
}

class _FullscreenVideoPlayerModalState extends State<FullscreenVideoPlayerModal> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    try {
      if (widget.url != null) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url!));
      } else if (widget.file != null) {
        _controller = VideoPlayerController.file(widget.file!);
      }

      if (_controller != null) {
        await _controller!.initialize();
        if (widget.initialPosition != null) {
          await _controller!.seekTo(widget.initialPosition!);
        }
        await _controller!.play();
        if (mounted) setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('[FullscreenVideoPlayerModal] Error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _isInitialized && _controller != null
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),

            // Top Bar with Close Button
            Positioned(
              top: 10,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // Center Play / Pause toggle on tap
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_controller != null && _isInitialized) {
                    setState(() {
                      if (_controller!.value.isPlaying) {
                        _controller!.pause();
                      } else {
                        _controller!.play();
                      }
                    });
                  }
                },
                child: _isInitialized && _controller != null && !_controller!.value.isPlaying
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 54),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // Bottom Progress Scrubber Bar
            if (_isInitialized && _controller != null)
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: VideoProgressIndicator(
                  _controller!,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFF2563EB),
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
