import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/session_card.dart';
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
    final sessionId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (sessionId != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to session',
              style: AppText.ui(size: 13, color: AppColors.textPrimary)),
          backgroundColor: AppColors.bgElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            content: Text('Failed to rename: $e',
                style: AppText.ui(size: 13)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(user?.email),
            if (_permissionDenied) _buildNotifBanner(),
            _buildScanButton(),
            Expanded(child: _buildBody()),
            if (kDebugMode && NotificationService.fcmToken != null)
              _FcmTokenDebugBar(token: NotificationService.fcmToken!),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String? email) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
          child: Row(
            children: [
              Text(
                'Ashral',
                style: AppText.display(size: 18, letterSpacing: -0.5),
              ),
              const Spacer(),
              if (email != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      email,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.mono(size: 11, color: AppColors.textMuted),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: AppColors.textMuted,
                tooltip: 'Refresh',
                onPressed: _loadSessions,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, size: 18),
                color: AppColors.textMuted,
                tooltip: 'Sign out',
                onPressed: () {
                  NotificationService.reset();
                  AuthService.signOut();
                },
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.borderSubtle),
      ],
    );
  }

  Widget _buildNotifBanner() {
    return Container(
      color: AppColors.waitingBg,
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      child: Row(
        children: [
          const Icon(Icons.notifications_off_outlined,
              size: 14, color: AppColors.waiting),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Notifications disabled — enable in Settings for agent alerts.',
              style: AppText.ui(
                  size: 12,
                  color: AppColors.waiting.withValues(alpha: 0.7)),
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
                style: AppText.ui(size: 11, weight: FontWeight.w600,
                    color: AppColors.waiting)),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: GestureDetector(
        onTap: _openScanner,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner_rounded,
                  size: 20, color: AppColors.bgDeep),
              const SizedBox(width: 10),
              Text(
                'Scan QR Code',
                style: AppText.ui(
                  size: 14,
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

  Widget _buildBody() {
    if (_loadingSessions) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.textMuted,
          strokeWidth: 1.5,
        ),
      );
    }

    if (_sessionsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  size: 36, color: AppColors.textMuted),
              const SizedBox(height: 14),
              Text(
                'Could not load sessions',
                style: AppText.ui(
                  size: 14,
                  weight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _sessionsError!,
                textAlign: TextAlign.center,
                style: AppText.ui(size: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _loadSessions,
                child: Text('Try again',
                    style: AppText.ui(size: 13, weight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sensors_off_rounded,
                size: 32, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No active sessions',
              style: AppText.ui(
                size: 14,
                weight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Scan a QR code from your agent terminal',
              style: AppText.ui(size: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
          child: Row(
            children: [
              Text('SESSIONS', style: AppText.sectionLabel()),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '${_sessions.length}',
                  style: AppText.mono(size: 10, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadSessions,
            color: AppColors.textPrimary,
            backgroundColor: AppColors.bgElevated,
            child: ListView.builder(
              padding: EdgeInsets.zero,
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
                    MaterialPageRoute(
                      builder: (_) => AgentOutputScreen(
                        sessionId: sessionId,
                        sessionMeta: session,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

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
