import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';

class ScanPage extends StatefulWidget {
  final Function(String)? onScanResult;
  
  const ScanPage({super.key, this.onScanResult});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with TickerProviderStateMixin {
  MobileScannerController? _controller;
  String? scanResult;
  StreamSubscription<Object?>? _subscription;
  
  final int animationTime = 2000;
  AnimationController? _animationController;
  bool isScan = false;
  bool _isInitializing = false;
  bool _hasScanned = false;

  // 缩放手势与闪光灯状态
  double _currentZoomScale = 0.0; // 0.0 (1x) ~ 1.0 (max zoom)
  double _baseZoomScale = 0.0;
  double _targetZoom = 0.0;
  double _appliedZoom = 0.0;
  bool _isApplyingZoom = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _initializeScanner();
  }

  @override
  void dispose() {
    // 先停止动画控制器
    if (_animationController != null) {
      _animationController?.stop();
      _animationController?.dispose();
      _animationController = null;
    }
    
    // 安全地停止相机和清理资源
    _subscription?.cancel();
    _controller?.dispose();
    _controller = null;
    
    isScan = false;
    super.dispose();
  }

  Future<void> _initializeScanner() async {
    if (!mounted) return;
    
    try {
      _controller = MobileScannerController(
        autoStart: false,
        cameraResolution: const Size(1920, 1080),
        detectionSpeed: DetectionSpeed.unrestricted,
        formats: [BarcodeFormat.qrCode],
        autoZoom: false,
      );
      
      await _controller!.start();
      
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        startScan();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  void startScan() async {
    isScan = true;
    _initAnimation();
  }

  void _initAnimation() {
    _animationController ??= AnimationController(
      vsync: this,
      duration: Duration(milliseconds: animationTime),
    )..addListener(() => setState(() {}))
      ..addStatusListener((state) {
        if (!mounted) {
          return;
        }

        if (state == AnimationStatus.completed) {
          Future.delayed(Duration(seconds: 1), () {
            if (_animationController != null && _animationController!.status != AnimationStatus.dismissed) {
              _animationController?.reverse();
            }
          });
        } else if (state == AnimationStatus.dismissed) {
          Future.delayed(Duration(seconds: 1), () {
            if (_animationController != null && _animationController!.status != AnimationStatus.forward) {
              _animationController?.forward();
            }
          });
        }
      });

    _animationController?.forward();
  }

  void stop() {
    if (!isScan) return;

    isScan = false;
    _controller?.stop();
    
    if (_animationController != null) {
      _animationController?.stop();
      _animationController?.reset();
    }
  }


  void scanImage(String path) async {
    if (_hasScanned) return;
    try {
      final barcodeCapture = await _controller?.analyzeImage(path);
      stop();
      if (mounted && barcodeCapture != null && barcodeCapture.barcodes.isNotEmpty) {
        final code = barcodeCapture.barcodes.first.rawValue;
        if (code != null) {
          _handleScanResult(code);
        }
      } else {
        await _controller?.start();
      }
    } catch (e) {
      debugPrint('Failed to analyze image: $e');
    }
  }

  void _updateZoom(double newZoom) {
    if (!mounted) return;
    final clamped = newZoom.clamp(0.0, 1.0);
    _targetZoom = clamped;
    if ((clamped - _currentZoomScale).abs() > 0.001) {
      setState(() {
        _currentZoomScale = clamped;
      });
    }
    _applyZoomPipeline();
  }

  void _applyZoomPipeline() async {
    if (_isApplyingZoom || _controller == null) return;
    _isApplyingZoom = true;
    try {
      while ((_targetZoom - _appliedZoom).abs() > 0.001) {
        final toApply = _targetZoom;
        await _controller?.setZoomScale(toApply);
        _appliedZoom = toApply;
      }
    } catch (e) {
      debugPrint('Zoom error: $e');
    } finally {
      _isApplyingZoom = false;
    }
  }

  void _toggleTorch() async {
    try {
      await _controller?.toggleTorch();
      setState(() {
        _isTorchOn = !_isTorchOn;
      });
    } catch (e) {
      debugPrint('Toggle torch error: $e');
    }
  }

  Widget _buildZoomButton(String label, double targetZoom) {
    final bool isSelected = (_currentZoomScale - targetZoom).abs() <= 0.05;
    return GestureDetector(
      onTap: () => _updateZoom(targetZoom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white12,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildZoomChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: LayoutBuilder(builder: (context, constraints) {
        final qrScanSize = constraints.maxWidth * 0.85;
        final mediaQuery = MediaQuery.of(context);
        final scanBoxTop = (constraints.maxHeight - qrScanSize) * 0.333333;
        final scanBoxBottom = scanBoxTop + qrScanSize;

        return Stack(
          children: [
            // 全屏双指捏合缩放与点击聚焦手势监听
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (details) {
                  _baseZoomScale = _currentZoomScale;
                },
                onScaleUpdate: (details) {
                  if (details.pointerCount >= 2) {
                    final double newZoom = (_baseZoomScale + (details.scale - 1.0) * 0.75).clamp(0.0, 1.0);
                    _updateZoom(newZoom);
                  }
                },
                onScaleEnd: (details) {
                  _baseZoomScale = _currentZoomScale;
                },
                onDoubleTap: () {
                  // 双击在 1.0x 与 2.0x 间快速切换
                  final target = _currentZoomScale > 0.05 ? 0.0 : 0.25;
                  _baseZoomScale = target;
                  _updateZoom(target);
                },
                onTapUp: (details) async {
                  // 点击屏幕任意位置触发对焦
                  final size = MediaQuery.sizeOf(context);
                  final relativeX = details.globalPosition.dx / size.width;
                  final relativeY = details.globalPosition.dy / size.height;
                  try {
                    await _controller?.setFocusPoint(Offset(relativeX, relativeY));
                  } catch (_) {}
                },
                child: MobileScanner(
                  controller: _controller,
                  tapToFocus: false, // 禁用内部手势探测器，避免吞噬双指缩放手势
                  onDetect: (BarcodeCapture capture) {
                    if (capture.barcodes.isNotEmpty) {
                      final code = capture.barcodes.first.rawValue;
                      debugPrint('条码内容：$code');
                      if (code != null) {
                        _handleScanResult(code);
                      }
                    }
                  },
                ),
              ),
            ),
            // 在初始化期间显示加载指示器
            if (_isInitializing)
              const IgnorePointer(
                child: Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                ),
              ),
            // 扫描框 (IgnorePointer 确保触摸事件直接穿透至下方手势层)
            Positioned(
              left: (constraints.maxWidth - qrScanSize) / 2,
              top: scanBoxTop,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: QrScanBoxPainter(
                    boxLineColor: Theme.of(context).colorScheme.primary,
                    animationValue: _animationController?.value ?? 0,
                    isForward: _animationController?.status == AnimationStatus.forward,
                  ),
                  child: SizedBox(width: qrScanSize, height: qrScanSize),
                ),
              ),
            ),
            // 扫描框下方：快速缩放倍率切换胶囊与手势提示
            Positioned(
              top: scanBoxBottom + 20,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildZoomButton('1.0x', 0.0),
                        const SizedBox(width: 4),
                        _buildZoomButton('2.0x', 0.25),
                        const SizedBox(width: 4),
                        _buildZoomButton('3.0x', 0.50),
                        if ((_currentZoomScale - 0.0).abs() > 0.05 &&
                            (_currentZoomScale - 0.25).abs() > 0.05 &&
                            (_currentZoomScale - 0.50).abs() > 0.05) ...[
                          const SizedBox(width: 4),
                          _buildZoomChip('${(1.0 + _currentZoomScale * 4.0).toStringAsFixed(1)}x'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const IgnorePointer(
                    child: Text(
                      '双指捏合缩放 · 远距离扫码更清晰',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 底部操作栏（相册、手电筒、取消）
            Positioned(
              width: constraints.maxWidth,
              bottom: constraints.maxHeight == mediaQuery.size.height ? 12 + mediaQuery.padding.bottom : 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    onPressed: () async {
                      final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);
                      if (image == null) return;
                      scanImage(image.path);
                    },
                    icon: const Icon(Icons.photo_library, color: Colors.white, size: 32),
                    tooltip: '相册导入',
                  ),
                  IconButton(
                    onPressed: _toggleTorch,
                    icon: Icon(
                      _isTorchOn ? Icons.flash_on : Icons.flash_off,
                      color: _isTorchOn ? Colors.amberAccent : Colors.white,
                      size: 32,
                    ),
                    tooltip: _isTorchOn ? '关闭闪光灯' : '打开闪光灯',
                  ),
                  TextButton(
                    onPressed: () {
                      stop();
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      '取消', 
                      style: TextStyle(color: Colors.white, fontSize: 18)
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }



  void _handleScanResult(String data) async {
    if (!mounted || _hasScanned) return;
    _hasScanned = true;
    
    // 先停止扫描
    stop();
    
    if (!mounted) return;
    try {
      // 必须先退出当前扫码页，回到课程列表页面，避免后续弹窗被意外 pop 导致黑屏
      Navigator.of(context).pop(data);
      widget.onScanResult?.call(data);
    } catch (e) {
      debugPrint('Navigator $e');
    }
  }
}

// 自定义扫描框绘制器
class QrScanBoxPainter extends CustomPainter {
  final double animationValue;
  final bool isForward;
  final Color boxLineColor;

  QrScanBoxPainter({
    required this.animationValue, 
    required this.isForward, 
    required this.boxLineColor
  });

  @override
  void paint(Canvas canvas, Size size) {
    final borderRadius = BorderRadius.all(Radius.circular(12)).toRRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    canvas.drawRRect(
      borderRadius,
      Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path();
    // leftTop
    path.moveTo(0, 50);
    path.lineTo(0, 12);
    path.quadraticBezierTo(0, 0, 12, 0);
    path.lineTo(50, 0);
    // rightTop
    path.moveTo(size.width - 50, 0);
    path.lineTo(size.width - 12, 0);
    path.quadraticBezierTo(size.width, 0, size.width, 12);
    path.lineTo(size.width, 50);
    // rightBottom
    path.moveTo(size.width, size.height - 50);
    path.lineTo(size.width, size.height - 12);
    path.quadraticBezierTo(size.width, size.height, size.width - 12, size.height);
    path.lineTo(size.width - 50, size.height);
    // leftBottom
    path.moveTo(50, size.height);
    path.lineTo(12, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - 12);
    path.lineTo(0, size.height - 50);

    canvas.drawPath(path, borderPaint);

    canvas.clipRRect(BorderRadius.all(Radius.circular(12)).toRRect(Offset.zero & size));

    // 绘制扫描线
    final linePaint = Paint()
      ..color = boxLineColor
      ..strokeWidth = 2.0;
    final lineY = size.height * animationValue;
    canvas.drawLine(
      Offset(0, lineY),
      Offset(size.width, lineY),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(QrScanBoxPainter oldDelegate) => animationValue != oldDelegate.animationValue;

  @override
  bool shouldRebuildSemantics(QrScanBoxPainter oldDelegate) => animationValue != oldDelegate.animationValue;
}