import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import '../widgets/session_card.dart';
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
        const SnackBar(
          content: Text('Connected to session'),
          behavior: SnackBarBehavior.floating,
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
            content: Text('Failed to leave: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _renameSession(String sessionId, String? customName) async {
    // Optimistic update
    setState(() {
      final idx = _sessions.indexWhere(
          (s) => (s['sessionId'] ?? s['id']) == sessionId);
      if (idx != -1) {
        _sessions[idx] = Map.of(_sessions[idx])..['customName'] = customName;
      }
    });

    try {
      await SessionService.renameSession(sessionId, customName);
    } catch (e) {
      // Revert on failure
      _loadSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to rename: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Ashral',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        actions: [
          if (user?.email != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  user!.email!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh sessions',
            onPressed: _loadSessions,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () {
              NotificationService.reset();
              AuthService.signOut();
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_permissionDenied)
            MaterialBanner(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              leading: const Icon(Icons.notifications_off_outlined),
              content: const Text(
                'Notifications are disabled. Enable them in Settings to receive agent alerts.',
              ),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _permissionDenied = false),
                  child: const Text('Dismiss'),
                ),
              ],
            ),

          // Scan QR button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
            child: FilledButton.icon(
              onPressed: _openScanner,
              icon: const Icon(Icons.qr_code_scanner, size: 26),
              label: const Text('Scan QR Code'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                textStyle: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          // Sessions list
          Expanded(child: _buildSessionsList(colorScheme)),

          // Debug FCM token
          if (kDebugMode && NotificationService.fcmToken != null)
            _FcmTokenDebugBar(token: NotificationService.fcmToken!),
        ],
      ),
    );
  }

  Widget _buildSessionsList(ColorScheme colorScheme) {
    if (_loadingSessions) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_sessionsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: colorScheme.error),
              const SizedBox(height: 12),
              Text('Could not load sessions',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: colorScheme.error)),
              const SizedBox(height: 6),
              Text(_sessionsError!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.5))),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadSessions,
                child: const Text('Retry'),
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
            Icon(Icons.sensors_off,
                size: 52, color: colorScheme.outlineVariant),
            const SizedBox(height: 14),
            Text('No active sessions',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 4),
            Text('Scan a QR code from your agent terminal',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.4))),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
          child: Text(
            'ACTIVE SESSIONS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.5),
                letterSpacing: 1),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadSessions,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _sessions.length,
              itemBuilder: (context, i) {
                final session = _sessions[i];
                final sessionId =
                    session['sessionId'] as String? ?? session['id'] as String? ?? '';
                return SessionCard(
                  session: session,
                  onLeave: () => _leaveSession(sessionId),
                  onRename: (customName) =>
                      _renameSession(sessionId, customName),
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
