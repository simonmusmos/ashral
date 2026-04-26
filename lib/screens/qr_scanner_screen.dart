import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../config/constants.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController();
  bool _processing = false;
  String? _errorMessage;

  late final AnimationController _scanCtrl;
  late final Animation<double> _scanAnim;

  static const _viewfinderSize = 256.0;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scanAnim =
        CurvedAnimation(parent: _scanCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scanCtrl.dispose();
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

    String? candidate = _extractCandidate(rawValue);
    if (candidate == null) {
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
      // Resolve 8-char short IDs to full UUIDs before joining
      final sessionId = _isShortId(candidate)
          ? await SessionService.resolveShortId(candidate)
          : candidate;

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

  // Returns the raw session ID or short code from a URL, bare UUID, or short code.
  String? _extractCandidate(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith(kQrUrlPrefix)) {
      final uri = Uri.tryParse(trimmed);
      final id = uri?.pathSegments.lastOrNull ?? '';
      return id.isNotEmpty ? id : null;
    }
    if (!trimmed.contains('/') && trimmed.isNotEmpty) return trimmed;
    return null;
  }

  static bool _isShortId(String s) =>
      RegExp(r'^[0-9a-f]{8}$', caseSensitive: false).hasMatch(s);

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

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
      backgroundColor: AppColors.bgBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AppColors.border),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 36,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 22),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Enter session code', style: AppText.display(size: 18)),
            const SizedBox(height: 4),
            Text(
              'The 8-character code shown in your terminal.',
              style: AppText.ui(size: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
            _OtpInput(
              controller: codeController,
              onCompleted: () => Navigator.pop(ctx, codeController.text),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: Text('Cancel',
                        style: AppText.ui(size: 14, weight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: codeController,
                    builder: (_, value, __) => FilledButton(
                      onPressed: value.text.length == 8
                          ? () => Navigator.pop(ctx, value.text)
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.textPrimary,
                        foregroundColor: AppColors.bgDeep,
                        disabledBackgroundColor:
                            AppColors.textPrimary.withValues(alpha: 0.25),
                      ),
                      child: Text('Continue',
                          style: AppText.ui(
                              size: 14,
                              weight: FontWeight.w600,
                              color: AppColors.bgDeep)),
                    ),
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
      backgroundColor: AppColors.bgBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AppColors.border),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 36,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 22),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Name this session', style: AppText.display(size: 18)),
            const SizedBox(height: 4),
            Text(
              "Give it a name you'll recognise (optional).",
              style: AppText.ui(size: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: AppText.ui(size: 15),
              decoration: const InputDecoration(
                hintText: 'e.g. My MacBook, Work laptop…',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: Text('Cancel',
                        style: AppText.ui(
                            size: 14, weight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, controller.text.trim()),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.textPrimary,
                      foregroundColor: AppColors.bgDeep,
                    ),
                    child: Text('Connect',
                        style: AppText.ui(
                            size: 14,
                            weight: FontWeight.w600,
                            color: AppColors.bgDeep)),
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
    final mq = MediaQuery.of(context);
    final screenSize = mq.size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera feed ─────────────────────────────────────────────────
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // ── Dim overlay with viewfinder cutout ──────────────────────────
          CustomPaint(
            size: screenSize,
            painter: _OverlayPainter(
              viewfinderSize: _viewfinderSize,
              screenSize: screenSize,
            ),
          ),

          // ── Animated scan line ──────────────────────────────────────────
          if (!_processing)
            AnimatedBuilder(
              animation: _scanAnim,
              builder: (_, __) {
                final cx = screenSize.width / 2;
                final cy = screenSize.height / 2;
                final left = cx - _viewfinderSize / 2;
                final top = cy - _viewfinderSize / 2;
                return Positioned(
                  left: left,
                  top: top + _scanAnim.value * (_viewfinderSize - 2),
                  width: _viewfinderSize,
                  height: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.ai.withValues(alpha: 0.85),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          // ── Corner brackets ─────────────────────────────────────────────
          ..._buildCorners(screenSize),

          // ── Top header ──────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    _IconBtn(
                      icon: CupertinoIcons.xmark,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      'Scan QR Code',
                      style: AppText.ui(
                          size: 15, weight: FontWeight.w600),
                    ),
                    const Spacer(),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom panel ─────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xD4000000),
                    border: Border(
                        top: BorderSide(color: AppColors.borderSubtle)),
                  ),
                  padding: EdgeInsets.fromLTRB(
                      24, 24, 24, mq.padding.bottom + 24),
                  child: _processing
                      ? _buildProcessingState()
                      : _errorMessage != null
                          ? _buildErrorState()
                          : _buildIdleState(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom panel states ───────────────────────────────────────────────────

  Widget _buildIdleState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Point your camera at the QR code in your terminal',
          textAlign: TextAlign.center,
          style: AppText.ui(size: 14, color: AppColors.textMuted, height: 1.5),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _AltButton(
                icon: CupertinoIcons.photo,
                label: 'Photo library',
                onTap: _pickFromGallery,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AltButton(
                icon: CupertinoIcons.keyboard,
                label: 'Enter code',
                onTap: _enterManually,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProcessingState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CupertinoActivityIndicator(
            color: AppColors.textMuted, radius: 10),
        const SizedBox(height: 12),
        Text(
          'Joining session…',
          style: AppText.ui(size: 13, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.errorBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.errorBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(CupertinoIcons.exclamationmark_circle,
                    size: 15, color: AppColors.error),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: AppText.ui(
                      size: 13, color: AppColors.error, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: () => setState(() => _errorMessage = null),
            child:
                Text('Try again', style: AppText.ui(size: 14, weight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }

  // ── Corner brackets ───────────────────────────────────────────────────────

  List<Widget> _buildCorners(Size screen) {
    final cx = screen.width / 2;
    final cy = screen.height / 2;
    const half = _viewfinderSize / 2;
    const sz = 24.0;

    Widget corner(double left, double top, bool flipH, bool flipV) =>
        Positioned(
          left: left,
          top: top,
          child: CustomPaint(
            size: const Size(sz, sz),
            painter: _CornerPainter(
              flipH: flipH,
              flipV: flipV,
              color: Colors.white,
              thickness: 2.5,
              radius: 3,
            ),
          ),
        );

    return [
      corner(cx - half, cy - half, false, false),
      corner(cx + half - sz, cy - half, true, false),
      corner(cx - half, cy + half - sz, false, true),
      corner(cx + half - sz, cy + half - sz, true, true),
    ];
  }
}

// ── Overlay painter ────────────────────────────────────────────────────────────

class _OverlayPainter extends CustomPainter {
  final double viewfinderSize;
  final Size screenSize;

  const _OverlayPainter({
    required this.viewfinderSize,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final viewfinderRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: viewfinderSize,
      height: viewfinderSize,
    );
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
          viewfinderRect, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
        path, Paint()..color = const Color(0xBB000000));
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.viewfinderSize != viewfinderSize;
}

// ── Corner painter ─────────────────────────────────────────────────────────────

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

// ── Alt entry button ───────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 7),
            Text(
              label,
              style: AppText.ui(
                size: 13,
                weight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Icon button ────────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

// ── OTP input ──────────────────────────────────────────────────────────────────

class _OtpInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onCompleted;

  const _OtpInput({required this.controller, this.onCompleted});

  @override
  State<_OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<_OtpInput> {
  static const _length = 8;
  late final FocusNode _focus;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode()..addListener(_onFocusChange);
    widget.controller.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _hasFocus = _focus.hasFocus);
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.controller.text.length == _length) {
      widget.onCompleted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return SizedBox(
      height: 52,
      child: Stack(
        children: [
          // Visual cells — pointer events pass through to the hidden field
          IgnorePointer(
            child: Row(
              children: [
                for (int i = 0; i < _length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _OtpCell(
                      char: i < text.length ? text[i].toUpperCase() : null,
                      isActive: _hasFocus && i == text.length,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Invisible text field that owns focus and captures keystrokes
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                textCapitalization: TextCapitalization.none,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                  LengthLimitingTextInputFormatter(_length),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── OTP cell ───────────────────────────────────────────────────────────────────

class _OtpCell extends StatelessWidget {
  final String? char;
  final bool isActive;

  const _OtpCell({this.char, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive
              ? AppColors.ai
              : char != null
                  ? AppColors.border
                  : AppColors.borderSubtle,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      alignment: Alignment.center,
      child: char != null
          ? Text(
              char!,
              style: AppText.mono(
                size: 18,
                weight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            )
          : isActive
              ? const _BlinkingCursor()
              : null,
    );
  }
}

// ── Blinking cursor ────────────────────────────────────────────────────────────

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 2,
        height: 22,
        decoration: BoxDecoration(
          color: AppColors.ai,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
