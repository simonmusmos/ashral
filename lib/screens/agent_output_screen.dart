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
  Timer? _elapsedTimer;
  bool _autoScroll = true;
  Map<String, dynamic>? _pendingAction;
  bool _responding = false;
  Map<String, dynamic>? _sessionDetail;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _poll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _elapsedTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.offset >=
        _scrollController.position.maxScrollExtent - 60;
    if (atBottom != _autoScroll) {
      setState(() => _autoScroll = atBottom);
    }
  }

  // ── Elapsed time ──────────────────────────────────────────────────────────

  void _startElapsedTimer(DateTime startedAt) {
    _elapsedTimer?.cancel();
    _elapsed = DateTime.now().difference(startedAt);
    final isLive = AppStatus.isLive(_status);
    if (!isLive) return; // static elapsed for completed sessions
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(startedAt));
    });
  }

  String get _elapsedLabel {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes.remainder(60);
    final s = _elapsed.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  // ── Polling ───────────────────────────────────────────────────────────────

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

      // Parse createdAt for elapsed timer
      DateTime? startedAt;
      final rawCreatedAt = detail['createdAt'];
      if (rawCreatedAt is Map && rawCreatedAt['_seconds'] != null) {
        startedAt = DateTime.fromMillisecondsSinceEpoch(
            (rawCreatedAt['_seconds'] as int) * 1000);
      }

      setState(() {
        _initialLoading = false;
        _error = null;
        _sessionDetail = detail.isNotEmpty ? detail : _sessionDetail;
        if (!_responding) _pendingAction = pendingAction;
      });

      if (startedAt != null) _startElapsedTimer(startedAt);

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
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  // ── Data helpers ──────────────────────────────────────────────────────────

  String get _displayName {
    final detail = _sessionDetail;
    final meta = widget.sessionMeta;
    if (detail != null) {
      final n = detail['name'] as String?;
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
    return (_sessionDetail?['agent'] as String?) ??
        (widget.sessionMeta?['agent'] as String?) ??
        '';
  }

  String get _status {
    return (_sessionDetail?['status'] as String?) ??
        (widget.sessionMeta?['status'] as String?) ??
        '';
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
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final hasPending = _pendingAction != null;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        bottom: false,
        child: _initialLoading
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
                      Column(
                        children: [
                          _buildHeader(),
                          Expanded(child: _buildBody()),
                        ],
                      ),
                      if (hasPending)
                        _buildActionBar(_pendingAction!, bottomPad),
                    ],
                  ),
      ),
      floatingActionButton: !_autoScroll && _chunks.isNotEmpty
          ? FloatingActionButton.small(
              onPressed: () {
                setState(() => _autoScroll = true);
                _scrollToBottom();
              },
              backgroundColor: AppColors.bgElevated,
              foregroundColor: AppColors.textSecondary,
              elevation: 3,
              child: const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
            )
          : null,
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final status = _status;
    final palette = status.isNotEmpty ? AppStatus.palette(status) : null;
    final isLive = AppStatus.isLive(status);
    final isCompleted =
        status.toLowerCase() == 'completed' || status.toLowerCase() == 'done';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(
          bottom: BorderSide(color: AppColors.borderSubtle),
          // Glow border for live sessions
          left: isLive
              ? const BorderSide(color: AppColors.running, width: 2)
              : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: back + name + actions
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chevron_left_rounded,
                        size: 22, color: AppColors.ai),
                    Text(
                      'Sessions',
                      style: AppText.ui(
                          size: 15,
                          weight: FontWeight.w500,
                          color: AppColors.ai),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_chunks.isNotEmpty)
                _IconBtn(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copy all output',
                  onTap: _copyAll,
                ),
              const SizedBox(width: 4),
              _IconBtn(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onTap: () {
                  _pollTimer?.cancel();
                  _poll();
                },
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Session card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.bgBase,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isLive
                    ? AppColors.runningBorder
                    : isCompleted
                        ? AppColors.successBorder
                        : AppColors.border,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Agent icon + session name
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AgentBadge(agent: _agentName, size: 38),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.display(size: 18),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _agentName.isNotEmpty ? _agentName : widget.sessionId,
                            style: AppText.mono(
                                size: 11, color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (palette != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
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
                              status.toUpperCase(),
                              style: AppText.mono(
                                size: 10,
                                weight: FontWeight.w600,
                                color: palette.text,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Elapsed time chip
                      if (_elapsed != Duration.zero) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.bgElevated,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.schedule_rounded,
                                  size: 11, color: AppColors.textMuted),
                              const SizedBox(width: 5),
                              Text(
                                _elapsedLabel,
                                style: AppText.mono(
                                    size: 11, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const Spacer(),

                      // Chunk count
                      if (_chunks.isNotEmpty)
                        Text(
                          '${_chunks.length} chunks',
                          style: AppText.mono(
                              size: 10, color: AppColors.textMuted),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_chunks.isEmpty) return _buildEmptyState();
    return _buildTerminal();
  }

  Widget _buildTerminal() {
    return Column(
      children: [
        // Terminal title bar
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            border:
                Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              // Traffic lights
              _dot(const Color(0xFFFF5F57)),
              const SizedBox(width: 6),
              _dot(const Color(0xFFFFBD2E)),
              const SizedBox(width: 6),
              _dot(const Color(0xFF28C840)),
              const SizedBox(width: 12),
              Text(
                _displayName,
                style: AppText.mono(size: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),

        // Output lines
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
            itemCount: _chunks.length,
            itemBuilder: (context, i) {
              final chunk = _chunks[i];
              final text = chunk['text'] as String? ?? '';
              final stream = chunk['stream'] as String? ?? 'stdout';
              final isStderr = stream == 'stderr';
              return Text(
                text,
                style: AppText.mono(
                  size: 12,
                  height: 1.55,
                  color: isStderr
                      ? AppColors.terminalErr
                      : _lineColor(text),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static Widget _dot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  static Color _lineColor(String text) {
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
    final isLive = AppStatus.isLive(_status);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.terminal_rounded,
              size: 30, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(
            isLive ? 'Waiting for output…' : 'No output recorded',
            style: AppText.ui(size: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          if (isLive)
            Text(
              'Polling every 3 seconds',
              style: AppText.mono(size: 11, color: AppColors.textMuted),
            ),
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

  // ── Action bar ────────────────────────────────────────────────────────────

  Widget _buildActionBar(Map<String, dynamic> action, double bottomPad) {
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
        padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPad + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pending action label
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.waiting,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'ACTION REQUIRED',
                  style: AppText.sectionLabel(),
                ),
              ],
            ),
            if (question != null && question.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                question,
                style: AppText.ui(
                    size: 14, height: 1.5, color: AppColors.textPrimary),
              ),
            ],
            const SizedBox(height: 12),
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
                    size: 14,
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
          style: AppText.ui(size: 14, weight: FontWeight.w500)),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

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
