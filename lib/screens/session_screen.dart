import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/session_service.dart';
import '../widgets/session_card.dart';

class SessionScreen extends StatefulWidget {
  final String sessionId;
  final Map<String, dynamic>? sessionMeta;

  const SessionScreen({
    super.key,
    required this.sessionId,
    this.sessionMeta,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  String? _error;
  bool _responding = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _detail == null;
      _error = null;
    });
    try {
      final detail = await SessionService.getSessionDetail(widget.sessionId);
      if (!mounted) return;
      setState(() => _detail = detail);
      _scheduleRefreshIfActive(detail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleRefreshIfActive(Map<String, dynamic> detail) {
    _refreshTimer?.cancel();
    final status = (detail['status'] as String? ?? '').toLowerCase();
    final hasPending = detail['pendingAction'] != null;
    final isActive =
        hasPending || status == 'running' || status == 'active';
    if (isActive) {
      _refreshTimer = Timer(const Duration(seconds: 8), _load);
    }
  }

  Future<void> _respond(String action) async {
    setState(() => _responding = true);
    try {
      await SessionService.respondToAction(
        sessionId: widget.sessionId,
        action: action,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Failed: $e',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: const Color(0xFFF2F2F2)),
          ),
          backgroundColor: const Color(0xFF1E0A0A),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ));
      }
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  // ── Data helpers ──────────────────────────────────────────────────────────

  String get _displayName {
    final meta = widget.sessionMeta;
    if (_detail != null) {
      final cn = _detail!['customName'] as String?;
      if (cn != null && cn.isNotEmpty) return cn;
      final n = _detail!['name'] as String?;
      if (n != null && n.isNotEmpty) return n;
    }
    if (meta != null) {
      final cn = meta['customName'] as String?;
      if (cn != null && cn.isNotEmpty) return cn;
      final n = meta['name'] as String?;
      if (n != null && n.isNotEmpty) return n;
    }
    return widget.sessionId;
  }

  String get _agentName {
    return (_detail?['agent'] as String?) ??
        (widget.sessionMeta?['agent'] as String?) ??
        '';
  }

  String get _status {
    return (_detail?['status'] as String?) ?? '';
  }

  String? get _latestMessage {
    return _detail?['message'] as String? ??
        _detail?['latestMessage'] as String?;
  }

  List<String> get _terminalLines {
    final raw = _detail?['terminalOutput'];
    if (raw is List) return raw.cast<String>();
    if (raw is String && raw.isNotEmpty) return raw.split('\n');
    return [];
  }

  Map<String, dynamic>? get _pendingAction {
    final a = _detail?['pendingAction'];
    if (a is Map<String, dynamic>) return a;
    return null;
  }

  // ── Status helpers ────────────────────────────────────────────────────────

  static ({Color dot, Color bg, Color text}) _statusColors(String status) {
    switch (status.toLowerCase()) {
      case 'running':
      case 'active':
        return (
          dot: const Color(0xFF22C55E),
          bg: const Color(0xFF0D2016),
          text: const Color(0xFF4ADE80),
        );
      case 'waiting':
      case 'pending':
      case 'paused':
        return (
          dot: const Color(0xFFF59E0B),
          bg: const Color(0xFF1C1500),
          text: const Color(0xFFFBBF24),
        );
      case 'error':
      case 'failed':
        return (
          dot: const Color(0xFFEF4444),
          bg: const Color(0xFF1E0A0A),
          text: const Color(0xFFF87171),
        );
      default:
        return (
          dot: const Color(0xFF4A4A4A),
          bg: const Color(0xFF161616),
          text: const Color(0xFF6B7280),
        );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pending = _pendingAction;
    final hasPending = pending != null;

    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090909),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
          color: const Color(0xFF5C5C5C),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            AgentBadge(agent: _agentName),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                _displayName,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFF2F2F2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: const Color(0xFF4A4A4A),
            tooltip: 'Refresh',
            onPressed: _load,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFF181818)),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF333333),
                strokeWidth: 1.5,
              ),
            )
          : _error != null
              ? _buildError()
              : Stack(
                  children: [
                    _buildContent(hasPending),
                    if (hasPending) _buildActionBar(pending),
                  ],
                ),
    );
  }

  Widget _buildError() {
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
              'Could not load session',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF5C5C5C),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: const Color(0xFF333333)),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _load,
              child: Text('Try again',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool hasPending) {
    return ListView(
      padding: EdgeInsets.only(
        top: 24,
        left: 20,
        right: 20,
        bottom: hasPending ? 140 : 32,
      ),
      children: [
        if (_status.isNotEmpty) ...[
          _buildStatusChip(_status),
          const SizedBox(height: 24),
        ],
        if (_latestMessage != null && _latestMessage!.isNotEmpty) ...[
          _buildSection(
            label: 'LATEST MESSAGE',
            child: _buildMessageBox(_latestMessage!),
          ),
          const SizedBox(height: 20),
        ],
        if (_terminalLines.isNotEmpty) ...[
          _buildSection(
            label: 'TERMINAL',
            trailing: IconButton(
              icon: const Icon(Icons.copy_rounded, size: 14),
              color: const Color(0xFF3A3A3A),
              tooltip: 'Copy output',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: _terminalLines.join('\n')));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Copied',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: const Color(0xFFF2F2F2))),
                  backgroundColor: const Color(0xFF181818),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ));
              },
            ),
            child: _buildTerminalBox(_terminalLines),
          ),
          const SizedBox(height: 20),
        ],
        if (_pendingAction != null) ...[
          _buildSection(
            label: 'PENDING ACTION',
            child: _buildPendingActionBox(_pendingAction!),
          ),
        ],
        if (_detail != null &&
            _status.isEmpty &&
            _latestMessage == null &&
            _terminalLines.isEmpty &&
            _pendingAction == null)
          _buildEmptyState(),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    final colors = _statusColors(status);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.dot.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.dot,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                status,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.text,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required String label,
    required Widget child,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3A3A3A),
                letterSpacing: 1.5,
              ),
            ),
            if (trailing != null) ...[
              const Spacer(),
              trailing,
            ],
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildMessageBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Text(
        message,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          height: 1.55,
          color: const Color(0xFFD4D4D4),
        ),
      ),
    );
  }

  Widget _buildTerminalBox(List<String> lines) {
    // Show last 30 lines to keep the view tight
    final visible = lines.length > 30 ? lines.sublist(lines.length - 30) : lines;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1A1A1A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: visible
            .map((line) => Text(
                  line,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 11,
                    height: 1.6,
                    color: _terminalLineColor(line),
                  ),
                ))
            .toList(),
      ),
    );
  }

  static Color _terminalLineColor(String line) {
    final l = line.trim();
    if (l.startsWith('error') || l.startsWith('Error') || l.startsWith('ERR')) {
      return const Color(0xFFF87171);
    }
    if (l.startsWith('warn') || l.startsWith('Warn') || l.startsWith('WARN')) {
      return const Color(0xFFFBBF24);
    }
    if (l.startsWith('\$') || l.startsWith('>')) {
      return const Color(0xFF7DD3FC);
    }
    if (l.startsWith('✓') || l.startsWith('✔') || l.startsWith('Done') || l.startsWith('SUCCESS')) {
      return const Color(0xFF4ADE80);
    }
    return const Color(0xFF6B7280);
  }

  Widget _buildPendingActionBox(Map<String, dynamic> action) {
    final description = action['description'] as String? ??
        action['message'] as String? ??
        action['type'] as String? ??
        'Action required';
    final type = action['type'] as String? ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1500),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3D2E00)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (type.isNotEmpty) ...[
            Text(
              type.toUpperCase(),
              style: GoogleFonts.ibmPlexMono(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF78716C),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            description,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.5,
              color: const Color(0xFFE7C97C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_empty_rounded,
                size: 28, color: Color(0xFF222222)),
            const SizedBox(height: 12),
            Text(
              'No activity yet',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: const Color(0xFF383838),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(Map<String, dynamic> action) {
    final options = action['options'] as List<dynamic>?;
    final hasOptions = options != null && options.isNotEmpty;

    // Determine button set: use explicit options if provided, else approve/deny
    final List<String> actions =
        hasOptions ? options.cast<String>() : ['deny', 'approve'];

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF090909),
          border: Border(top: BorderSide(color: Color(0xFF1A1A1A))),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Row(
          children: [
            for (int i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: _buildActionButton(actions[i])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String action) {
    final isPositive =
        action == 'approve' || action == 'yes' || action == 'allow';
    final label = action[0].toUpperCase() + action.substring(1);

    if (isPositive) {
      return FilledButton(
        onPressed: _responding ? null : () => _respond(action),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFF2F2F2),
          foregroundColor: const Color(0xFF090909),
          minimumSize: const Size.fromHeight(50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _responding
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFF090909),
                ),
              )
            : Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.w600)),
      );
    }

    return OutlinedButton(
      onPressed: _responding ? null : () => _respond(action),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFEF4444),
        side: const BorderSide(color: Color(0xFF2A0A0A)),
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14, fontWeight: FontWeight.w500)),
    );
  }
}
