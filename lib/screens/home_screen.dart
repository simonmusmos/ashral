import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/session_card.dart';
import '../widgets/usage_bar.dart';
import 'agent_output_screen.dart';
import 'qr_scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _permissionDenied = false;
  List<Map<String, dynamic>> _sessions = [];
  bool _loadingSessions = true;
  String? _sessionsError;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadSessions();
  }

  Future<void> _initNotifications() async {
    final granted = await NotificationService.initialize();
    if (!granted && mounted) setState(() => _permissionDenied = true);
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loadingSessions = true;
      _sessionsError = null;
    });
    try {
      final sessions = await SessionService.getSessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (e) {
      if (mounted) setState(() => _sessionsError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingSessions = false);
    }
  }

  Future<void> _openScanner() async {
    HapticFeedback.lightImpact();
    final sessionId = await Navigator.push<String>(
      context,
      CupertinoPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (sessionId != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to session',
              style: AppText.ui(size: 13, color: AppColors.textPrimary)),
          backgroundColor: AppColors.bgElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      _loadSessions();
    }
  }

  Future<void> _leaveSession(String sessionId) async {
    try {
      await SessionService.leaveSession(sessionId);
      _loadSessions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to leave: $e',
                style: AppText.ui(size: 13, color: AppColors.textPrimary)),
            backgroundColor: AppColors.errorBg,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _renameSession(String sessionId, String? customName) async {
    setState(() {
      final idx = _sessions
          .indexWhere((s) => (s['sessionId'] ?? s['id']) == sessionId);
      if (idx != -1) {
        _sessions[idx] = Map.of(_sessions[idx])..['customName'] = customName;
      }
    });
    try {
      await SessionService.renameSession(sessionId, customName);
    } catch (e) {
      _loadSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to rename: $e', style: AppText.ui(size: 13)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                if (_permissionDenied) _buildNotifBanner(),
                const UsageBar(),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
          // Scan button pinned at thumb level — always reachable
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.bgDeep,
                border: Border(top: BorderSide(color: AppColors.borderSubtle)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: _ScanButton(onTap: _openScanner),
            ),
          ),
          if (kDebugMode && NotificationService.fcmToken != null)
            _FcmTokenDebugBar(token: NotificationService.fcmToken!),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final liveCount = _sessions
        .where((s) => AppStatus.isLive(s['status'] as String? ?? ''))
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'A',
                    style: AppText.display(
                        size: 21, weight: FontWeight.w800, color: AppColors.ai),
                  ),
                  TextSpan(
                    text: 'shral',
                    style: AppText.display(size: 21, letterSpacing: -0.5),
                  ),
                ],
              ),
            ),
            if (liveCount > 0) ...[
              const SizedBox(width: 8),
              _LiveBadge(count: liveCount),
            ],
            const Spacer(),
            _NavIconBtn(
              icon: CupertinoIcons.arrow_clockwise,
              onTap: _loadSessions,
              tooltip: 'Refresh',
            ),
            const SizedBox(width: 2),
            _NavIconBtn(
              icon: CupertinoIcons.square_arrow_right,
              onTap: () {
                NotificationService.reset();
                AuthService.signOut();
              },
              tooltip: 'Sign out',
            ),
          ],
        ),
    );
  }

  Widget _buildNotifBanner() {
    return Container(
      color: AppColors.waitingBg,
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      child: Row(
        children: [
          const Icon(CupertinoIcons.bell_slash,
              size: 13, color: AppColors.waiting),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Notifications disabled — enable in Settings for agent alerts.',
              style: AppText.ui(
                  size: 12,
                  color: AppColors.waiting.withValues(alpha: 0.85)),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _permissionDenied = false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.waiting,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Text('Dismiss',
                style: AppText.ui(
                    size: 11,
                    weight: FontWeight.w600,
                    color: AppColors.waiting)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingSessions) {
      return const Center(
        child: CupertinoActivityIndicator(color: AppColors.textMuted),
      );
    }

    if (_sessionsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.wifi_slash,
                  size: 34, color: AppColors.textMuted),
              const SizedBox(height: 16),
              Text(
                'Could not load sessions',
                style: AppText.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _sessionsError!,
                textAlign: TextAlign.center,
                style: AppText.ui(size: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: _loadSessions,
                child: Text('Try again',
                    style: AppText.ui(size: 14, weight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.antenna_radiowaves_left_right,
                size: 30,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 20),
              Text(
                'No sessions yet',
                style: AppText.display(
                    size: 18, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 7),
              Text(
                'Scan a QR code from a running agent to get started',
                textAlign: TextAlign.center,
                style: AppText.ui(
                    size: 13, height: 1.5, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    // Cards render directly — no "SESSIONS" header needed
    return RefreshIndicator(
      onRefresh: _loadSessions,
      color: AppColors.textPrimary,
      backgroundColor: AppColors.bgElevated,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
        itemCount: _sessions.length,
        itemBuilder: (context, i) {
          final session = _sessions[i];
          final sessionId = session['sessionId'] as String? ??
              session['id'] as String? ??
              '';
          return SessionCard(
            session: session,
            onLeave: () => _leaveSession(sessionId),
            onRename: (customName) =>
                _renameSession(sessionId, customName),
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => AgentOutputScreen(
                  sessionId: sessionId,
                  sessionMeta: session,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Live badge ─────────────────────────────────────────────────────────────────

class _LiveBadge extends StatelessWidget {
  final int count;
  const _LiveBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.runningBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.runningBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AppColors.running,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$count live',
            style: AppText.mono(
                size: 10, weight: FontWeight.w600, color: AppColors.running),
          ),
        ],
      ),
    );
  }
}

// ── Scan button ───────────────────────────────────────────────────────────────

class _ScanButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ScanButton({required this.onTap});

  @override
  State<_ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<_ScanButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.qrcode_viewfinder,
                size: 18,
                color: AppColors.bgDeep,
              ),
              const SizedBox(width: 8),
              Text(
                'Scan to connect',
                style: AppText.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  color: AppColors.bgDeep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Nav icon button ────────────────────────────────────────────────────────────

class _NavIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _NavIconBtn(
      {required this.icon, required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          child: Icon(icon, size: 17, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

// ── FCM debug bar ─────────────────────────────────────────────────────────────

class _FcmTokenDebugBar extends StatelessWidget {
  final String token;
  const _FcmTokenDebugBar({required this.token});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.amber.shade100,
      padding: const EdgeInsets.only(left: 12, right: 4, top: 6, bottom: 6),
      child: Row(
        children: [
          const Text('FCM ',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
          Expanded(
            child: Text(token,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Copy FCM token',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: token));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('FCM token copied'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
