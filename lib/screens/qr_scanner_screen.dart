import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: Color(0xFF1E1E1E)),
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
            Text(
              'Name this session',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Give this session a name you'll recognise (optional).",
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: const Color(0xFF4A4A4A)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. My MacBook, Work laptop…',
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14, color: const Color(0xFF333333)),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF222222)),
                      foregroundColor: const Color(0xFF5C5C5C),
                    ),
                    child: Text('Cancel',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, controller.text.trim()),
                    child: Text('Connect',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600)),
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
        title: Text(
          'Scan QR Code',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
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
            width: 256,
            height: 256,
            decoration: BoxDecoration(
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1),
              borderRadius: BorderRadius.circular(12),
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
                  const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 1.5,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Joining session…',
                    style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFF888888), fontSize: 13),
                  ),
                ] else if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF160808),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2E1212)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Color(0xFFEF4444), size: 15),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFFEF4444), fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => setState(() => _errorMessage = null),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFAAAAAA)),
                    child: Text('Try again',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ] else
                  Text(
                    'Point at the QR code in your terminal',
                    style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFF555555), fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCorners() {
    const size = 26.0;
    const thickness = 2.5;
    const color = Colors.white;
    const radius = 3.0;
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
