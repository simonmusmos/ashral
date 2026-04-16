import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/session_card.dart';

class AgentOutputScreen extends StatefulWidget {
  final String sessionId;
  final Map<String, dynamic>? sessionMeta;

  const AgentOutputScreen({
    super.key,
    required this.sessionId,
    this.sessionMeta,
  });

  @override
  State<AgentOutputScreen> createState() => _AgentOutputScreenState();
}

class _AgentOutputScreenState extends State<AgentOutputScreen> {
  final List<Map<String, dynamic>> _chunks = [];
  final Set<String> _seenIds = {};
  final ScrollController _scrollController = ScrollController();

  bool _initialLoading = true;
  String? _error;
  Timer? _pollTimer;
  bool _autoScroll = true;
  Map<String, dynamic>? _pendingAction;
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _poll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.offset >=
        _scrollController.position.maxScrollExtent - 40;
    if (atBottom != _autoScroll) {
      setState(() => _autoScroll = atBottom);
    }
  }

  Future<void> _poll() async {
    try {
      final results = await Future.wait([
        SessionService.fetchSessionOutput(widget.sessionId),
        SessionService.getSessionDetail(widget.sessionId)
            .catchError((_) => <String, dynamic>{}),
      ]);

      if (!mounted) return;

      final incoming = results[0] as List<Map<String, dynamic>>;
      final detail = results[1] as Map<String, dynamic>;

      bool added = false;
      for (final chunk in incoming) {
        final id = chunk['chunkId'] as String? ?? '';
        if (id.isNotEmpty && _seenIds.contains(id)) continue;
        if (id.isNotEmpty) _seenIds.add(id);
        _chunks.add(chunk);
        added = true;
      }

      final rawAction = detail['pendingAction'];
      final pendingAction =
          rawAction is Map<String, dynamic> ? rawAction : null;

      setState(() {
        _initialLoading = false;
        _error = null;
        if (!_responding) _pendingAction = pendingAction;
      });

      if (added && _autoScroll) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _error = e.toString();
      });
    }

    _pollTimer?.cancel();
    _pollTimer = Timer(const Duration(seconds: 3), _poll);
  }

  Future<void> _respond(String action) async {
    _pollTimer?.cancel();
    setState(() => _responding = true);
    try {
      await SessionService.respondToAction(
        sessionId: widget.sessionId,
        action: action,
      );
      if (mounted) setState(() => _pendingAction = null);
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
      if (mounted) {
        setState(() => _responding = false);
        _pollTimer = Timer(const Duration(seconds: 2), _poll);
      }
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  String get _displayName {
    final meta = widget.sessionMeta;
    if (meta != null) {
      final cn = meta['customName'] as String?;
      if (cn != null && cn.isNotEmpty) return cn;
      final n = meta['name'] as String?;
      if (n != null && n.isNotEmpty) return n;
    }
    return widget.sessionId;
  }

  String get _agentName {
    return (widget.sessionMeta?['agent'] as String?) ?? '';
  }

  String get _status {
    return (widget.sessionMeta?['status'] as String?) ?? '';
  }

  void _copyAll() {
    final text = _chunks.map((c) => c['text'] as String? ?? '').join('');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Output copied',
          style: AppText.ui(size: 13, color: AppColors.textPrimary)),
      backgroundColor: AppColors.bgElevated,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                style: AppText.ui(
                    size: 15, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          if (_chunks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 17),
              color: AppColors.textMuted,
              tooltip: 'Copy all output',
              onPressed: _copyAll,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: AppColors.textMuted,
            tooltip: 'Refresh',
            onPressed: () {
              _pollTimer?.cancel();
              _poll();
            },
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.borderSubtle),
        ),
      ),
      body: _initialLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.textMuted,
                strokeWidth: 1.5,
              ),
            )
          : _error != null && _chunks.isEmpty
              ? _buildError()
              : Stack(
                  children: [
                    _buildOutput(),
                    if (_pendingAction != null) _buildActionBar(_pendingAction!),
                  ],
                ),
      floatingActionButton: !_autoScroll && _chunks.isNotEmpty
          ? FloatingActionButton.small(
              onPressed: () {
                setState(() => _autoScroll = true);
                _scrollToBottom();
              },
              backgroundColor: AppColors.bgElevated,
              foregroundColor: AppColors.textSecondary,
              elevation: 2,
              child: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            )
          : null,
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
              'Could not load output',
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
              onPressed: () {
                _pollTimer?.cancel();
                setState(() {
                  _initialLoading = true;
                  _error = null;
                });
                _poll();
              },
              child: Text('Try again',
                  style: AppText.ui(size: 13, weight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutput() {
    return Column(
      children: [
        if (_status.isNotEmpty) _buildStatusBar(),
        Expanded(
          child: _chunks.isEmpty ? _buildEmptyState() : _buildTerminal(),
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    final palette = AppStatus.palette(_status);
    final isLive = AppStatus.isLive(_status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: palette.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLive)
                  _PulsingDot(color: palette.dot)
                else
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: palette.dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 7),
                Text(
                  _status,
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
          const Spacer(),
          Text(
            '${_chunks.length} chunks',
            style: AppText.mono(size: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminal() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      itemCount: _chunks.length,
      itemBuilder: (context, i) {
        final chunk = _chunks[i];
        final text = chunk['text'] as String? ?? '';
        final stream = chunk['stream'] as String? ?? 'stdout';
        final isStderr = stream == 'stderr';

        return Text(
          text,
          style: AppText.mono(
            size: 11.5,
            height: 1.55,
            color: isStderr
                ? AppColors.terminalErr
                : _outputLineColor(text),
          ),
        );
      },
    );
  }

  static Color _outputLineColor(String text) {
    final l = text.trim();
    if (l.startsWith('error') ||
        l.startsWith('Error') ||
        l.startsWith('ERR') ||
        l.startsWith('✗')) {
      return AppColors.terminalErr;
    }
    if (l.startsWith('warn') ||
        l.startsWith('Warn') ||
        l.startsWith('WARN') ||
        l.startsWith('⚠')) {
      return AppColors.terminalWarn;
    }
    if (l.startsWith(r'$') || l.startsWith('>') || l.startsWith('#')) {
      return AppColors.terminalCmd;
    }
    if (l.startsWith('✓') ||
        l.startsWith('✔') ||
        l.startsWith('Done') ||
        l.startsWith('SUCCESS') ||
        l.startsWith('Completed')) {
      return AppColors.terminalSuccess;
    }
    return AppColors.terminalText;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.terminal_rounded,
              size: 28, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'No output yet',
            style: AppText.ui(size: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Polling every 3 seconds…',
            style: AppText.mono(size: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  // ── Action bar ─────────────────────────────────────────────────────────────

  Widget _buildActionBar(Map<String, dynamic> action) {
    final rawOptions = action['options'] as List<dynamic>?;
    final options = rawOptions?.cast<String>() ?? ['approve', 'deny'];
    final question = action['question'] as String?;

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
          16,
          16,
          16,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (question != null && question.isNotEmpty) ...[
              Text(
                question,
                style: AppText.ui(
                    size: 13, height: 1.5, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
            ],
            ...List.generate((options.length / 2).ceil(), (rowIndex) {
              final start = rowIndex * 2;
              final end = (start + 2).clamp(0, options.length);
              final rowOptions = options.sublist(start, end);
              return Padding(
                padding: EdgeInsets.only(top: rowIndex > 0 ? 8 : 0),
                child: Row(
                  children: [
                    for (int i = 0; i < rowOptions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _buildOptionButton(rowOptions[i]),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton(String option) {
    final lower = option.toLowerCase().trim();
    final isPositive = lower == 'approve' ||
        lower == 'yes' ||
        lower == 'allow' ||
        lower.startsWith('1.');
    final label = option.length > 40 ? '${option.substring(0, 38)}…' : option;

    final match = RegExp(r'^(\d+)\.').firstMatch(option.trim());
    final action = match != null ? match.group(1)! : option;

    if (isPositive) {
      return FilledButton(
        onPressed: _responding ? null : () => _respond(action),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: AppColors.bgDeep,
          minimumSize: const Size.fromHeight(50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _responding
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: AppColors.bgDeep),
              )
            : Text(label,
                style: AppText.ui(
                    size: 13,
                    weight: FontWeight.w600,
                    color: AppColors.bgDeep)),
      );
    }

    return OutlinedButton(
      onPressed: _responding ? null : () => _respond(action),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size.fromHeight(50),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label,
          style:
              AppText.ui(size: 13, weight: FontWeight.w500)),
    );
  }
}

// ── Pulsing dot ────────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
