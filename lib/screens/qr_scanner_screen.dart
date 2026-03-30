import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../config/constants.dart';
import '../services/session_service.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _processing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;

    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) return;

    // Validate URL format
    if (!rawValue.startsWith(kQrUrlPrefix)) return;

    final uri = Uri.tryParse(rawValue);
    final sessionId = uri?.pathSegments.lastOrNull ?? '';
    if (sessionId.isEmpty) return;

    await HapticFeedback.mediumImpact();
    await _controller.stop();

    // Ask for a custom name before connecting
    if (!mounted) return;
    final nameResult = await _askForCustomName();
    if (nameResult == null) {
      // User cancelled — resume scanning
      await _controller.start();
      return;
    }

    setState(() {
      _processing = true;
      _errorMessage = null;
    });

    try {
      await SessionService.joinSession(
        sessionId: sessionId,
        customName: nameResult.isEmpty ? null : nameResult,
      );

      if (mounted) Navigator.pop(context, sessionId);
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        setState(() {
          _processing = false;
          _errorMessage = message;
        });
        await _controller.start();
      }
    }
  }

  /// Returns the entered name, empty string if skipped, or null if cancelled.
  Future<String?> _askForCustomName() async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Name this session',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              "Give this session a name you'll recognise (optional).",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. My MacBook, Work laptop…',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, controller.text.trim()),
                    child: const Text('Connect'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan QR Code'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Camera
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Viewfinder overlay
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2.5),
              borderRadius: BorderRadius.circular(16),
            ),
          ),

          // Corner accents
          ..._buildCorners(),

          // Bottom status area
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: Column(
              children: [
                if (_processing) ...[
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 12),
                  const Text('Joining session…',
                      style: TextStyle(color: Colors.white70)),
                ] else if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () =>
                        setState(() => _errorMessage = null),
                    child: const Text('Try again',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ] else
                  const Text(
                    'Point at the QR code in your terminal',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCorners() {
    const size = 28.0;
    const thickness = 4.0;
    const color = Colors.white;
    const radius = 4.0;
    const offset = 130 - thickness / 2; // half of 260px viewfinder

    Widget corner(double top, double left, bool flipH, bool flipV) {
      return Positioned(
        top: MediaQuery.of(context).size.height / 2 +
            (flipV ? offset : -offset - size),
        left: MediaQuery.of(context).size.width / 2 +
            (flipH ? offset : -offset - size),
        child: CustomPaint(
          size: const Size(size, size),
          painter: _CornerPainter(
              flipH: flipH, flipV: flipV, color: color, thickness: thickness, radius: radius),
        ),
      );
    }

    return [
      corner(0, 0, false, false),
      corner(0, 0, true, false),
      corner(0, 0, false, true),
      corner(0, 0, true, true),
    ];
  }
}

class _CornerPainter extends CustomPainter {
  final bool flipH;
  final bool flipV;
  final Color color;
  final double thickness;
  final double radius;

  const _CornerPainter({
    required this.flipH,
    required this.flipV,
    required this.color,
    required this.thickness,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    canvas.save();
    if (flipH) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    if (flipV) {
      canvas.translate(0, size.height);
      canvas.scale(1, -1);
    }

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, radius)
      ..arcToPoint(Offset(radius, 0),
          radius: Radius.circular(radius), clockwise: true)
      ..lineTo(size.width, 0);

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}
