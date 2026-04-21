import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
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
    await _handleRawValue(rawValue);
  }

  Future<void> _handleRawValue(String rawValue) async {
    if (_processing) return;

    final sessionId = _extractSessionId(rawValue);
    if (sessionId == null) {
      setState(() => _errorMessage = 'Invalid QR code');
      return;
    }

    await HapticFeedback.mediumImpact();
    await _controller.stop();

    if (!mounted) return;
    final nameResult = await _askForCustomName();
    if (nameResult == null) {
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

  String? _extractSessionId(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith(kQrUrlPrefix)) {
      final uri = Uri.tryParse(trimmed);
      final id = uri?.pathSegments.lastOrNull ?? '';
      return id.isNotEmpty ? id : null;
    }
    // Accept a bare session ID (no slashes, reasonable length)
    if (!trimmed.contains('/') && trimmed.length >= 8) return trimmed;
    return null;
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    // analyzeImage must be called before stop() on iOS — stopping first hangs.
    BarcodeCapture? capture;
    try {
      capture = await _controller
          .analyzeImage(file.path)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      capture = null;
    }

    await _controller.stop();
    if (!mounted) return;

    final rawValue = capture?.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) {
      setState(() => _errorMessage = 'No QR code found in image');
      await _controller.start();
      return;
    }
    await _handleRawValue(rawValue);
  }

  Future<void> _enterManually() async {
    await _controller.stop();
    if (!mounted) return;

    final codeController = TextEditingController();
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
              'Enter code',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Paste the session URL or ID from your terminal.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: const Color(0xFF4A4A4A)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: codeController,
              autofocus: true,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'https://ashral-web.vercel.app/join/…',
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: const Color(0xFF333333)),
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
                        Navigator.pop(ctx, codeController.text.trim()),
                    child: Text('Continue',
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
    Future.delayed(const Duration(milliseconds: 400), codeController.dispose);

    if (result == null || result.isEmpty) {
      await _controller.start();
      return;
    }
    await _handleRawValue(result);
  }

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
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
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
                  color: Colors.white.withValues(alpha: 0.15), width: 1),
              borderRadius: BorderRadius.circular(12),
            ),
          ),

          ..._buildCorners(),

          // Bottom status / action area
          Positioned(
            bottom: 48,
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
                const SizedBox(height: 20),
                // Alternative entry options
                Row(
                  children: [
                    Expanded(
                      child: _AltButton(
                        icon: Icons.photo_library_outlined,
                        label: 'Choose photo',
                        onTap: _processing ? null : _pickFromGallery,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AltButton(
                        icon: Icons.keyboard_outlined,
                        label: 'Enter code',
                        onTap: _processing ? null : _enterManually,
                      ),
                    ),
                  ],
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
    const offset = 130 - thickness / 2;

    Widget corner(double top, double left, bool flipH, bool flipV) {
      return Positioned(
        top: MediaQuery.of(context).size.height / 2 +
            (flipV ? offset : -offset - size),
        left: MediaQuery.of(context).size.width / 2 +
            (flipH ? offset : -offset - size),
        child: CustomPaint(
          size: const Size(size, size),
          painter: _CornerPainter(
              flipH: flipH,
              flipV: flipV,
              color: color,
              thickness: thickness,
              radius: radius),
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

class _AltButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _AltButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1E1E1E)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF888888)),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF888888),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
