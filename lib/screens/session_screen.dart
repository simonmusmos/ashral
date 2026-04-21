import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pulsing_dot.dart';
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
  String? _respondingAction;
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
    final isActive = hasPending || status == 'running' || status == 'active';
    if (isActive) {
      _refreshTimer = Timer(const Duration(seconds: 8), _load);
    }
  }

  Future<void> _respond(String action) async {
    setState(() => _respondingAction = action);
    try {
      await SessionService.respondToAction(
        sessionId: widget.sessionId,
        action: action,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e',
              style: AppText.ui(size: 13, color: AppColors.textPrimary)),
          backgroundColor: AppColors.errorBg,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _respondingAction = null);
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

  String? get _agentSessionId =>
      _detail?['agentSessionId'] as String?;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pending = _pendingAction;
    // Only show the action bar when explicit options are provided.
    final hasPending = pending != null &&
        (pending['options'] as List?)?.isNotEmpty == true;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgDeep,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
          color: AppColors.textSecondary,
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            AgentBadge(agent: _agentName, size: 30),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                _displayName,
                overflow: TextOverflow.ellipsis,
                style: AppText.ui(size: 15, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: AppColors.textMuted,
            tooltip: 'Refresh',
            onPressed: _load,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.borderSubtle),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.textMuted,
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
                size: 36, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(
              'Could not load session',
              style: AppText.ui(
                  size: 14,
                  weight: FontWeight.w600,
                  color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppText.ui(size: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _load,
              child: Text('Try again',
                  style: AppText.ui(size: 13, weight: FontWeight.w500)),
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
              color: AppColors.textMuted,
              tooltip: 'Copy output',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: _terminalLines.join('\n')));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Copied',
                      style:
                          AppText.ui(size: 13, color: AppColors.textPrimary)),
                  backgroundColor: AppColors.bgElevated,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ));
              },
            ),
            child: _buildTerminalBox(_terminalLines),
          ),
          const SizedBox(height: 20),
        ],
        if (_pendingAction != null &&
            (_pendingAction!['options'] as List?)?.isNotEmpty == true) ...[
          _buildSection(
            label: 'PENDING ACTION',
            child: _buildPendingActionBox(_pendingAction!),
          ),
        ],
        if (_agentSessionId != null) ...[
          const SizedBox(height: 20),
          _buildSection(
            label: 'RESUME',
            child: _buildResumeBox(widget.sessionId),
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
    final palette = AppStatus.palette(status);
    final isLive = AppStatus.isLive(status);
    return Row(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: palette.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLive)
                PulsingDot(color: palette.dot)
              else
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: palette.dot,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                status,
                style: AppText.mono(
                  size: 11,
                  weight: FontWeight.w500,
                  color: palette.text,
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
            Text(label, style: AppText.sectionLabel()),
            if (trailing != null) ...[
              const Spacer(),
              trailing,
            ],
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  Widget _buildMessageBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: AppText.ui(size: 14, height: 1.6, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _buildTerminalBox(List<String> lines) {
    final visible =
        lines.length > 30 ? lines.sublist(lines.length - 30) : lines;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: visible
            .map((line) => Text(
                  line,
                  style: AppText.mono(
                    size: 11.5,
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
    if (l.startsWith('error') ||
        l.startsWith('Error') ||
        l.startsWith('ERR')) {
      return AppColors.terminalErr;
    }
    if (l.startsWith('warn') ||
        l.startsWith('Warn') ||
        l.startsWith('WARN')) {
      return AppColors.terminalWarn;
    }
    if (l.startsWith(r'$') || l.startsWith('>')) {
      return AppColors.terminalCmd;
    }
    if (l.startsWith('✓') ||
        l.startsWith('✔') ||
        l.startsWith('Done') ||
        l.startsWith('SUCCESS')) {
      return AppColors.terminalSuccess;
    }
    return AppColors.terminalText;
  }

  Widget _buildPendingActionBox(Map<String, dynamic> action) {
    final description = action['description'] as String? ??
        action['message'] as String? ??
        action['type'] as String? ??
        'Action required';
    final type = action['type'] as String? ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.waitingBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.waitingBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (type.isNotEmpty) ...[
            Text(
              type.toUpperCase(),
              style: AppText.mono(
                size: 10,
                weight: FontWeight.w600,
                color: AppColors.waiting.withValues(alpha: 0.6),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            description,
            style: AppText.ui(
                size: 14, height: 1.55, color: AppColors.waiting),
          ),
        ],
      ),
    );
  }

  Widget _buildResumeBox(String ashralSessionId) {
    final command = 'ashral resume $ashralSessionId';
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: command));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Command copied',
              style: AppText.ui(size: 13, color: AppColors.textPrimary)),
          backgroundColor: AppColors.bgElevated,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                command,
                style: AppText.mono(
                  size: 12,
                  color: AppColors.terminalCmd,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.copy_rounded, size: 14, color: AppColors.textMuted),
          ],
        ),
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
                size: 28, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'No activity yet',
              style: AppText.ui(size: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(Map<String, dynamic> action) {
    final options = action['options'] as List<dynamic>?;
    final hasOptions = options != null && options.isNotEmpty;
    final List<String> actions =
        hasOptions ? options.cast<String>() : ['deny', 'approve'];

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgDeep,
          border: Border(top: BorderSide(color: AppColors.border)),
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
    final isLoading = _respondingAction == action;
    final isBusy = _respondingAction != null;

    if (isPositive) {
      return IgnorePointer(
        ignoring: isBusy,
        child: Opacity(
          opacity: isBusy && !isLoading ? 0.45 : 1.0,
          child: FilledButton(
            onPressed: () => _respond(action),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: AppColors.bgDeep,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.bgDeep,
                    ),
                  )
                : Text(label,
                    style: AppText.ui(
                        size: 14,
                        weight: FontWeight.w600,
                        color: AppColors.bgDeep)),
          ),
        ),
      );
    }

    return IgnorePointer(
      ignoring: isBusy,
      child: Opacity(
        opacity: isBusy && !isLoading ? 0.45 : 1.0,
        child: OutlinedButton(
          onPressed: () => _respond(action),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error.withValues(alpha: 0.8),
            side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.textSecondary,
                  ),
                )
              : Text(label,
                  style: AppText.ui(size: 14, weight: FontWeight.w500)),
        ),
      ),
    );
  }
}
