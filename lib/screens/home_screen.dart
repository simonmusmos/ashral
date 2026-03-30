import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

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
        SnackBar(
          content: Text('Connected to session',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: const Color(0xFFF2F2F2))),
          backgroundColor: const Color(0xFF181818),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: const Color(0xFFF2F2F2))),
            backgroundColor: const Color(0xFF1E0A0A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
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
                style: GoogleFonts.plusJakartaSans(fontSize: 13)),
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
      backgroundColor: const Color(0xFF090909),
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
          padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
          child: Row(
            children: [
              Text(
                'Ashral',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFF2F2F2),
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              if (email != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Text(
                      email,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: const Color(0xFF3A3A3A),
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: const Color(0xFF4A4A4A),
                tooltip: 'Refresh',
                onPressed: _loadSessions,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, size: 18),
                color: const Color(0xFF4A4A4A),
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
        const Divider(height: 1, color: Color(0xFF181818)),
      ],
    );
  }

  Widget _buildNotifBanner() {
    return Container(
      color: const Color(0xFF0F0D00),
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      child: Row(
        children: [
          const Icon(Icons.notifications_off_outlined,
              size: 14, color: Color(0xFF666633)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Notifications disabled — enable in Settings for agent alerts.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: const Color(0xFF555533)),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _permissionDenied = false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF888855),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Text('Dismiss',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w600)),
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
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner_rounded,
                  size: 20, color: Color(0xFF090909)),
              const SizedBox(width: 10),
              Text(
                'Scan QR Code',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF090909),
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
          color: Color(0xFF333333),
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
                  size: 36, color: Color(0xFF2A2A2A)),
              const SizedBox(height: 14),
              Text(
                'Could not load sessions',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF5C5C5C),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _sessionsError!,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: const Color(0xFF333333)),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _loadSessions,
                child: Text('Try again',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w500)),
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
                size: 32, color: Color(0xFF222222)),
            const SizedBox(height: 16),
            Text(
              'No active sessions',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF383838),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Scan a QR code from your agent terminal',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: const Color(0xFF2A2A2A)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
          child: Row(
            children: [
              Text(
                'SESSIONS',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF3A3A3A),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF222222)),
                ),
                child: Text(
                  '${_sessions.length}',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 10,
                    color: const Color(0xFF4A4A4A),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadSessions,
            color: const Color(0xFFF2F2F2),
            backgroundColor: const Color(0xFF161616),
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
