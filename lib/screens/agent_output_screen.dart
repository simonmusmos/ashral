import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/session_service.dart';
import '../services/usage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pulsing_dot.dart';
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
  final Set<String> _seenTexts = {};
  final ScrollController _scrollController = ScrollController();

  bool _initialLoading = true;
  String? _error;
  Timer? _pollTimer;
  Timer? _elapsedTimer;
  bool _autoScroll = true;
  Map<String, dynamic>? _pendingAction;
  String? _respondingAction;
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

        // Deduplicate notification-formatted chunks: strip leading emoji chars
        // and skip if the same text was already shown (e.g. 🖥️-prefixed duplicates).
        final rawText = chunk['text'] as String? ?? '';
        final normalized = rawText
            .replaceAll(RegExp(r'^[\u{1F300}-\u{1FAFF}\s]+', unicode: true), '')
            .trim();
        if (normalized.isNotEmpty && _seenTexts.contains(normalized)) {
          if (id.isNotEmpty) _seenIds.add(id);
          continue;
        }
        if (normalized.isNotEmpty) _seenTexts.add(normalized);

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
        if (_respondingAction == null) _pendingAction = pendingAction;
      });

      // Track cost for daily/weekly usage accounting
      final cost = (detail['stats']?['cost'] as num?)?.toDouble();
      if (cost != null && cost > 0) {
        unawaited(UsageService.recordCost(widget.sessionId, cost));
      }

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
    setState(() => _respondingAction = action);
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
        setState(() => _respondingAction = null);
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

  String? get _agentSessionId =>
      _sessionDetail?['agentSessionId'] as String?;

  Map<String, dynamic>? get _stats {
    final s = _sessionDetail?['stats'];
    if (s is Map<String, dynamic>) return s;
    return null;
  }

  String _formatCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return '$n';
  }

  String _formatCost(double usd) {
    if (usd == 0) return '\$0';
    if (usd < 0.001) return '\$<0.001';
    if (usd < 1) return '\$${usd.toStringAsFixed(3)}';
    return '\$${usd.toStringAsFixed(2)}';
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
    // Only show the action bar when explicit options are provided — conversational
    // "waiting for input" (pendingAction with no options) is shown via the status chip.
    final hasPending = _pendingAction != null &&
        (_pendingAction!['options'] as List?)?.isNotEmpty == true;

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

          // ── Stats row ──────────────────────────────────────────────────────
          if (_stats != null) ...[
            const SizedBox(height: 10),
            _buildStatsRow(_stats!),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsRow(Map<String, dynamic> stats) {
    int parseInt(dynamic v) => (v as num?)?.toInt() ?? 0;
    final costUsd = (stats['cost'] as num?)?.toDouble() ?? 0.0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _AnimatedStatCard(
              value: parseInt(stats['calls']),
              label: 'CALLS',
              color: AppColors.ai,
              formatter: _formatCount,
            )),
            const SizedBox(width: 8),
            Expanded(child: _AnimatedStatCard(
              value: parseInt(stats['files']),
              label: 'FILES',
              color: AppColors.running,
              formatter: _formatCount,
            )),
            const SizedBox(width: 8),
            Expanded(child: _AnimatedStatCard(
              value: parseInt(stats['tokens']),
              label: 'TOKENS',
              color: AppColors.textSecondary,
              formatter: _formatCount,
            )),
          ],
        ),
        const SizedBox(height: 8),
        _AnimatedCostCard(value: costUsd, formatter: _formatCost),
      ],
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_chunks.isEmpty) {
      final agentSessionId = _agentSessionId;
      final showResume = agentSessionId != null && !AppStatus.isLive(_status);
      if (showResume) {
        return Column(
          children: [
            Expanded(child: _buildEmptyState()),
            _buildResumeFooter(agentSessionId),
          ],
        );
      }
      return _buildEmptyState();
    }
    return _buildTerminal();
  }

  // Detect CLI/tool system messages that shouldn't appear as user/AI output.
  static bool _isSystemChunk(String text) {
    final t = text.trimLeft();
    const prefixes = [
      'Base directory for this skill:',
      '<system-reminder>',
      '<function_calls>',
      '<?xml',
      '### Skill:',
      'The user stepped away',
    ];
    // Claude Code sub-agent task prompts contain "Prior knowledge:" — never user-typed
    if (t.contains('Prior knowledge:')) return true;
    if (prefixes.any((p) => t.startsWith(p))) return true;
    // Skill guide rule-list format: - `rule-name` - description (Apple HIG)
    final ruleLines =
        RegExp(r"^- `[a-z][a-z0-9-]+` - ", multiLine: true).allMatches(text).length;
    if (ruleLines >= 3) return true;
    // Skill checklist review format: - [ ] description
    final checkboxLines =
        RegExp(r"^- \[ \]", multiLine: true).allMatches(text).length;
    if (checkboxLines >= 4) return true;
    // Skill path references that appear throughout the usage/script sections
    if (text.contains('ui-ux-pro-max') ||
        text.contains('design-system/MASTER.md') ||
        RegExp(r'skills/[a-z][a-z0-9-]+/').hasMatch(text)) {
      return true;
    }
    return false;
  }

  Widget _buildTerminal() {
    final agentSessionId = _agentSessionId;
    final showResume = agentSessionId != null && !AppStatus.isLive(_status);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
      itemCount: _chunks.length + (showResume ? 1 : 0),
      itemBuilder: (context, i) {
        if (showResume && i == _chunks.length) {
          return _buildResumeFooter(agentSessionId);
        }
        final chunk = _chunks[i];
        final text = (chunk['text'] as String? ?? '').trim();
        if (text.isEmpty) return const SizedBox.shrink();
        if (_isSystemChunk(text)) return const SizedBox.shrink();
        final isUser = chunk['stream'] == 'stderr';
        return isUser ? _UserMessage(text: text) : _AiMessage(text: text);
      },
    );
  }

  Widget _buildResumeFooter(String agentSessionId) {
    final shortId = (_sessionDetail?['shortId'] as String?) ??
        widget.sessionId.replaceAll('-', '').substring(0, 8);
    final command = 'ashral resume $shortId';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: AppColors.borderSubtle),
          const SizedBox(height: 12),
          Text('RESUME', style: AppText.sectionLabel()),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Command copied',
                    style: AppText.ui(size: 13, color: AppColors.textPrimary)),
                backgroundColor: AppColors.bgElevated,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ));
            },
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  const Icon(Icons.copy_rounded,
                      size: 14, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
        decoration: BoxDecoration(
          color: AppColors.bgDeep,
          border: Border(
            top: BorderSide(
              color: AppColors.waiting.withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.waiting.withValues(alpha: 0.07),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPad + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pending action label
            Row(
              children: [
                PulsingDot(color: AppColors.waiting, size: 6),
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
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: isLoading
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
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AppColors.textSecondary),
                )
              : Text(label,
                  style: AppText.ui(size: 14, weight: FontWeight.w500)),
        ),
      ),
    );
  }
}

// ── Chat message widgets ───────────────────────────────────────────────────────

class _UserMessage extends StatelessWidget {
  final String text;
  const _UserMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1, right: 10),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.person_rounded, size: 13, color: AppColors.textMuted),
          ),
          Expanded(
            child: Text(
              text,
              style: AppText.ui(
                size: 13,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiMessage extends StatelessWidget {
  final String text;
  const _AiMessage({required this.text});

  static final MarkdownStyleSheet _sheet = MarkdownStyleSheet(
    // Body text
    p: AppText.ui(size: 13.5, height: 1.65, color: AppColors.textPrimary),
    pPadding: const EdgeInsets.only(bottom: 8),

    // Headings — display font, stepped sizes
    h1: AppText.display(size: 20, weight: FontWeight.w700),
    h1Padding: const EdgeInsets.only(top: 16, bottom: 6),
    h2: AppText.display(size: 17, weight: FontWeight.w700),
    h2Padding: const EdgeInsets.only(top: 14, bottom: 6),
    h3: AppText.display(size: 15, weight: FontWeight.w600),
    h3Padding: const EdgeInsets.only(top: 10, bottom: 4),
    h4: AppText.ui(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary),
    h4Padding: const EdgeInsets.only(top: 8, bottom: 4),

    // Inline code
    code: AppText.mono(
      size: 12,
      color: AppColors.ai,
    ),
    codeblockDecoration: BoxDecoration(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    codeblockPadding: const EdgeInsets.all(14),

    // Blockquote
    blockquote: AppText.ui(size: 13, color: AppColors.textSecondary, height: 1.6),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: AppColors.textMuted, width: 3),
      ),
    ),
    blockquotePadding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),

    // Lists
    listBullet: AppText.ui(size: 13, color: AppColors.textMuted),
    listBulletPadding: const EdgeInsets.only(right: 8),
    listIndent: 16,

    // Horizontal rule
    horizontalRuleDecoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),

    // Table
    tableHead: AppText.mono(size: 11, weight: FontWeight.w600, color: AppColors.textSecondary),
    tableBody: AppText.mono(size: 11, color: AppColors.textPrimary),
    tableBorder: TableBorder.all(color: AppColors.border, width: 1),
    tableHeadAlign: TextAlign.left,

    // Strong / em
    strong: AppText.ui(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary),
    em: AppText.ui(size: 13.5, color: AppColors.textSecondary)
        .copyWith(fontStyle: FontStyle.italic),

    // Spacing
    blockSpacing: 4,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: AppColors.aiBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.ai.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.ai),
          ),
          Expanded(
            child: MarkdownBody(
              data: text,
              styleSheet: _sheet,
              softLineBreak: true,
              selectable: true,
              builders: {'code': _CodeBlockBuilder()},
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom code block builder — applies monospace + terminal lime for fenced blocks.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    dynamic element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent as String? ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          code.trimRight(),
          style: AppText.mono(
            size: 12,
            height: 1.6,
            color: AppColors.terminalText,
          ),
        ),
      ),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _AnimatedStatCard extends StatefulWidget {
  final int value;
  final String label;
  final Color color;
  final String Function(int) formatter;

  const _AnimatedStatCard({
    required this.value,
    required this.label,
    required this.color,
    required this.formatter,
  });

  @override
  State<_AnimatedStatCard> createState() => _AnimatedStatCardState();
}

class _AnimatedStatCardState extends State<_AnimatedStatCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _countAnim;
  late Animation<double> _glowAnim;
  double _fromValue = 0;

  @override
  void initState() {
    super.initState();
    _fromValue = widget.value.toDouble();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _countAnim = _controller.drive(
      Tween<double>(begin: _fromValue, end: _fromValue)
          .chain(CurveTween(curve: Curves.easeOut)),
    );
    // Glow fades in then out — peaks at mid-animation
    _glowAnim = _controller.drive(
      TweenSequence([
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 70),
      ]),
    );
  }

  @override
  void didUpdateWidget(_AnimatedStatCard old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _fromValue = _countAnim.value;
      _countAnim = _controller.drive(
        Tween<double>(begin: _fromValue, end: widget.value.toDouble())
            .chain(CurveTween(curve: Curves.easeOut)),
      );
      _glowAnim = _controller.drive(
        TweenSequence([
          TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 70),
        ]),
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final displayed = _countAnim.value.round();
        final glow = _glowAnim.value;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: glow > 0.01
                  ? Color.lerp(AppColors.border, widget.color, glow * 0.5)!
                  : AppColors.border,
            ),
            boxShadow: glow > 0.01
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: glow * 0.12),
                      blurRadius: 12,
                      spreadRadius: 0,
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.formatter(displayed),
                style: AppText.display(
                  size: 17,
                  color: glow > 0.01
                      ? Color.lerp(widget.color, Colors.white, glow * 0.3)!
                      : widget.color,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.label,
                style: AppText.mono(
                  size: 9,
                  weight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnimatedCostCard extends StatefulWidget {
  final double value;
  final String Function(double) formatter;

  const _AnimatedCostCard({required this.value, required this.formatter});

  @override
  State<_AnimatedCostCard> createState() => _AnimatedCostCardState();
}

class _AnimatedCostCardState extends State<_AnimatedCostCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _countAnim;
  late Animation<double> _glowAnim;
  double _fromValue = 0;

  static const _color = Color(0xFF818CF8); // indigo — distinct from other cards

  @override
  void initState() {
    super.initState();
    _fromValue = widget.value;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _countAnim = _controller.drive(
      Tween<double>(begin: _fromValue, end: _fromValue)
          .chain(CurveTween(curve: Curves.easeOut)),
    );
    _glowAnim = _controller.drive(
      TweenSequence([
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 25),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 75),
      ]),
    );
  }

  @override
  void didUpdateWidget(_AnimatedCostCard old) {
    super.didUpdateWidget(old);
    if ((old.value - widget.value).abs() > 0.000001) {
      _fromValue = _countAnim.value;
      _countAnim = _controller.drive(
        Tween<double>(begin: _fromValue, end: widget.value)
            .chain(CurveTween(curve: Curves.easeOut)),
      );
      _glowAnim = _controller.drive(
        TweenSequence([
          TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 25),
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 75),
        ]),
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final glow = _glowAnim.value;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: glow > 0.01
                  ? Color.lerp(AppColors.border, _color, glow * 0.5)!
                  : AppColors.border,
            ),
            boxShadow: glow > 0.01
                ? [BoxShadow(
                    color: _color.withValues(alpha: glow * 0.12),
                    blurRadius: 14,
                  )]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'EST. COST',
                style: AppText.mono(
                  size: 9,
                  weight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                widget.formatter(_countAnim.value),
                style: AppText.display(
                  size: 17,
                  color: glow > 0.01
                      ? Color.lerp(_color, Colors.white, glow * 0.3)!
                      : _color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

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
