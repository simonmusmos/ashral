import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
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
  final TextEditingController _messageController = TextEditingController();
  bool _isSendingMessage = false;
  bool _waitingForReply = false;

  final _headerKey = GlobalKey();
  double _headerExtent = 210.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _poll();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _elapsedTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _measureHeader() {
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && mounted) {
      final h = box.size.height;
      if ((h - _headerExtent).abs() > 1) setState(() => _headerExtent = h);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.offset >=
        _scrollController.position.maxScrollExtent - 60;
    if (atBottom != _autoScroll) setState(() => _autoScroll = atBottom);
  }

  void _startElapsedTimer(DateTime startedAt) {
    _elapsedTimer?.cancel();
    _elapsed = DateTime.now().difference(startedAt);
    if (!AppStatus.isLive(_status)) return;
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
      bool hasNewAiOutput = false;
      for (final chunk in incoming) {
        final id = chunk['chunkId'] as String? ?? '';
        if (id.isNotEmpty && _seenIds.contains(id)) continue;
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
        if (chunk['stream'] == 'stdout') hasNewAiOutput = true;
      }

      final rawAction = detail['pendingAction'];
      final pendingAction = rawAction is Map<String, dynamic> ? rawAction : null;

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
        // Capture whether we had a pending action BEFORE the update so we can
        // detect when a genuinely new one arrives (vs the same one persisting).
        final hadNoPendingAction = _pendingAction == null;
        if (_respondingAction == null) _pendingAction = pendingAction;
        // Stop the spinner only when Claude actually produced something new:
        // a fresh stdout chunk, or a brand-new pending action (question).
        final isNewPendingAction = hadNoPendingAction && pendingAction != null;
        if (hasNewAiOutput || isNewPendingAction) _waitingForReply = false;
      });

      final cost = (detail['stats']?['cost'] as num?)?.toDouble();
      if (cost != null && cost > 0) {
        unawaited(UsageService.recordCost(widget.sessionId, cost));
      }

      if (startedAt != null) _startElapsedTimer(startedAt);

      WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());

      if (added && _autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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

  Future<void> _respond(String action, {String? displayLabel}) async {
    _pollTimer?.cancel();
    HapticFeedback.mediumImpact();
    _addOptimisticMessage(displayLabel ?? action);
    setState(() {
      _respondingAction = action;
      _waitingForReply = true;
    });
    try {
      await SessionService.respondToAction(
          sessionId: widget.sessionId, action: action);
      if (mounted) setState(() => _pendingAction = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e',
              style: AppText.ui(size: 13, color: AppColors.textPrimary)),
          backgroundColor: AppColors.errorBg,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _respondingAction = null);
        _pollTimer = Timer(const Duration(seconds: 2), _poll);
      }
    }
  }

  void _addOptimisticMessage(String text) {
    final normalized = text
        .replaceAll(RegExp(r'^[\u{1F300}-\u{1FAFF}\s]+', unicode: true), '')
        .trim();
    if (normalized.isEmpty) return;
    final localId = 'opt_${DateTime.now().millisecondsSinceEpoch}';
    _seenIds.add(localId);
    _seenTexts.add(normalized);
    _chunks.add({'chunkId': localId, 'text': text, 'stream': 'stderr'});
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSendingMessage) return;
    HapticFeedback.mediumImpact();
    _messageController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    _addOptimisticMessage(text);
    setState(() {
      _isSendingMessage = true;
      _waitingForReply = true;
    });
    try {
      await SessionService.respondToAction(
          sessionId: widget.sessionId, action: text);
      if (mounted && _pendingAction != null) {
        setState(() => _pendingAction = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to send: $e',
              style: AppText.ui(size: 13, color: AppColors.textPrimary)),
          backgroundColor: AppColors.errorBg,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSendingMessage = false);
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

    // User's custom name always takes priority over the CLI-assigned name
    final customName = (meta?['customName'] as String?)?.trim() ??
        (detail?['customName'] as String?)?.trim();
    if (customName != null && customName.isNotEmpty) return customName;

    // Fall back to the session name set by the CLI
    final name = (detail?['name'] as String?)?.trim() ??
        (meta?['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;

    return widget.sessionId;
  }

  String get _agentName =>
      (_sessionDetail?['agent'] as String?) ??
      (widget.sessionMeta?['agent'] as String?) ??
      '';

  String get _status =>
      (_sessionDetail?['status'] as String?) ??
      (widget.sessionMeta?['status'] as String?) ??
      '';

  bool get _sessionAcceptsInput {
    final s = _status.toLowerCase();
    return s.isNotEmpty &&
        s != 'completed' &&
        s != 'error' &&
        s != 'terminated' &&
        s != 'done' &&
        s != 'failed';
  }

  Map<String, dynamic>? get _stats {
    final s = _sessionDetail?['stats'];
    return s is Map<String, dynamic> ? s : null;
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
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Output copied',
          style: AppText.ui(size: 13, color: AppColors.textPrimary)),
      backgroundColor: AppColors.bgElevated,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final hasPending = _pendingAction != null &&
        (_pendingAction!['options'] as List?)?.isNotEmpty == true;
    final isLive = AppStatus.isLive(_status);

    if (_initialLoading) {
      return const Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: Center(
            child: CupertinoActivityIndicator(color: AppColors.textMuted)),
      );
    }

    if (_error != null && _chunks.isEmpty) {
      return Scaffold(
          backgroundColor: AppColors.bgDeep,
          body: SafeArea(bottom: false, child: _buildError()));
    }

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildScrollableBody(
                hasPending: hasPending,
                isLive: isLive,
                bottomPad: bottomPad,
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildBlurHeader(),
            ),
            if (hasPending || _sessionAcceptsInput)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomBar(
                  hasPending: hasPending,
                  isLive: isLive,
                  bottomPad: bottomPad,
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: !_autoScroll && _chunks.isNotEmpty
          ? _ScrollToBottomFab(onTap: () {
              setState(() => _autoScroll = true);
              _scrollToBottom();
            })
          : null,
    );
  }

  // ── Frosted-glass header ──────────────────────────────────────────────────

  Widget _buildBlurHeader() {
    final status = _status;
    final palette = status.isNotEmpty ? AppStatus.palette(status) : null;
    final isLive = AppStatus.isLive(status);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          key: _headerKey,
          decoration: const BoxDecoration(
            color: Color(0xEB000000),
            border: Border(
              bottom: BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nav row
              Row(
                children: [
                  _BackButton(onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  }),
                  const Spacer(),
                  if (_chunks.isNotEmpty)
                    _HeaderAction(
                      icon: CupertinoIcons.doc_on_clipboard,
                      tooltip: 'Copy all',
                      onTap: _copyAll,
                    ),
                  const SizedBox(width: 2),
                  _HeaderAction(
                    icon: CupertinoIcons.arrow_clockwise,
                    tooltip: 'Refresh',
                    onTap: () {
                      _pollTimer?.cancel();
                      _poll();
                    },
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Identity row — flat, no wrapper card
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
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
                          style: AppText.display(size: 17),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            if (palette != null)
                              _StatusBadge(
                                  palette: palette,
                                  status: status,
                                  isLive: isLive),
                            if (_elapsed != Duration.zero) ...[
                              const SizedBox(width: 8),
                              _ElapsedChip(label: _elapsedLabel),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (_stats != null) ...[
                const SizedBox(height: 14),
                _buildStatsRow(_stats!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Stats sit flat in the header — no sub-container, just a hairline separator
  Widget _buildStatsRow(Map<String, dynamic> stats) {
    int parseInt(dynamic v) => (v as num?)?.toInt() ?? 0;
    final costUsd = (stats['cost'] as num?)?.toDouble() ?? 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 0.5, color: AppColors.borderSubtle),
        const SizedBox(height: 12),
        Row(
          children: [
            _AnimatedStatCell(
              value: parseInt(stats['calls']),
              label: 'calls',
              color: AppColors.ai,
              formatter: _formatCount,
            ),
            const _StatSep(),
            _AnimatedStatCell(
              value: parseInt(stats['files']),
              label: 'files',
              color: AppColors.running,
              formatter: _formatCount,
            ),
            const _StatSep(),
            _AnimatedStatCell(
              value: parseInt(stats['tokens']),
              label: 'tokens',
              color: AppColors.textSecondary,
              formatter: _formatCount,
            ),
            const _StatSep(),
            _AnimatedCostCell(value: costUsd, formatter: _formatCost),
          ],
        ),
      ],
    );
  }

  // ── Scrollable body ───────────────────────────────────────────────────────

  Widget _buildScrollableBody({
    required bool hasPending,
    required bool isLive,
    required double bottomPad,
  }) {
    if (_chunks.isEmpty) {
      final showResume = !isLive && (_status == 'terminated' || _status == 'completed');
      return Column(
        children: [
          SizedBox(height: _headerExtent),
          Expanded(child: _buildEmptyState()),
          if (showResume) _buildResumeFooter(),
          if (_sessionAcceptsInput) SizedBox(height: bottomPad + 72),
        ],
      );
    }
    return _buildTerminal(hasPending: hasPending, isLive: isLive, bottomPad: bottomPad);
  }

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
    if (t.contains('Prior knowledge:')) return true;
    if (prefixes.any((p) => t.startsWith(p))) return true;
    final ruleLines = RegExp(r"^- `[a-z][a-z0-9-]+` - ", multiLine: true)
        .allMatches(text)
        .length;
    if (ruleLines >= 3) return true;
    final checkboxLines =
        RegExp(r"^- \[ \]", multiLine: true).allMatches(text).length;
    if (checkboxLines >= 4) return true;
    if (text.contains('ui-ux-pro-max') ||
        text.contains('design-system/MASTER.md') ||
        RegExp(r'skills/[a-z][a-z0-9-]+/').hasMatch(text)) {
      return true;
    }
    return false;
  }

  Widget _buildTerminal({
    required bool hasPending,
    required bool isLive,
    required double bottomPad,
  }) {
    final showResume = !isLive && (_status == 'terminated' || _status == 'completed');
    final agentLabel = _displayName;

    final visibleChunks = <Map<String, dynamic>>[];
    for (final chunk in _chunks) {
      final text = (chunk['text'] as String? ?? '').trim();
      if (text.isEmpty) continue;
      if (_isSystemChunk(text)) continue;
      visibleChunks.add(chunk);
    }

    final showSpinner = _waitingForReply;
    return ListView.builder(
      controller: _scrollController,
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(
        0,
        _headerExtent + 8,
        0,
        hasPending && _sessionAcceptsInput
            ? bottomPad + 236
            : hasPending
                ? bottomPad + 160
                : _sessionAcceptsInput
                    ? bottomPad + 88
                    : 40,
      ),
      itemCount: visibleChunks.length + (showResume ? 1 : 0) + (showSpinner ? 1 : 0),
      itemBuilder: (context, i) {
        if (showResume && i == visibleChunks.length) {
          return _buildResumeFooter();
        }
        if (showSpinner && i == visibleChunks.length + (showResume ? 1 : 0)) {
          return const _WaitingSpinner();
        }
        final chunk = visibleChunks[i];
        final text = (chunk['text'] as String? ?? '').trim();
        final isUser = chunk['stream'] == 'stderr';

        final prevChunk = i > 0 ? visibleChunks[i - 1] : null;
        final prevIsUser =
            prevChunk != null && prevChunk['stream'] == 'stderr';
        final showSeparator = i == 0 || isUser != prevIsUser;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSeparator)
              Padding(
                padding: EdgeInsets.fromLTRB(16, i == 0 ? 6 : 18, 16, 6),
                child: Row(
                  children: [
                    Text(
                      isUser ? 'You' : agentLabel,
                      style: AppText.mono(
                          size: 10,
                          weight: FontWeight.w500,
                          color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                          height: 0.5, color: AppColors.borderSubtle),
                    ),
                  ],
                ),
              ),
            isUser ? _UserMessage(text: text) : _AiMessage(text: text),
          ],
        );
      },
    );
  }

  Widget _buildResumeFooter() {
    final shortId = (_sessionDetail?['shortId'] as String?) ??
        widget.sessionId.replaceAll('-', '').substring(0, 8);
    final command = 'ashral resume $shortId';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: AppColors.borderSubtle, height: 1, thickness: 0.5),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(CupertinoIcons.arrow_counterclockwise,
                  size: 12, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                'Resume this session',
                style: AppText.ui(size: 12, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _CopyableCommandBox(command: command),
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
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.textMuted.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
            child: Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.terminal_rounded,
                    size: 24, color: AppColors.textMuted),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isLive ? 'Waiting for output…' : 'No output recorded',
            style: AppText.ui(size: 14, color: AppColors.textSecondary),
          ),
          if (isLive) ...[
            const SizedBox(height: 5),
            Text(
              'Polling every 3 seconds',
              style: AppText.mono(size: 11, color: AppColors.textMuted),
            ),
          ],
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
            const Icon(CupertinoIcons.wifi_slash,
                size: 34, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'Could not load output',
              style: AppText.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppText.ui(size: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 24),
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
                  style: AppText.ui(size: 14, weight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom overlay: message input + optional pending-action bar ──────────

  Widget _buildBottomBar({
    required bool hasPending,
    required bool isLive,
    required double bottomPad,
  }) {
    final acceptsInput = _sessionAcceptsInput;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasPending)
          _buildActionBar(_pendingAction!, acceptsInput ? 0 : bottomPad),
        if (acceptsInput) _buildMessageInput(bottomPad),
      ],
    );
  }

  Widget _buildMessageInput(double bottomPad) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF2000000),
            border: Border(
              top: BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPad + 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: AppText.ui(size: 14, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Message Claude…',
                    hintStyle:
                        AppText.ui(size: 14, color: AppColors.textMuted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: AppColors.ai.withValues(alpha: 0.55)),
                    ),
                    filled: true,
                    fillColor: AppColors.bgElevated,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    isDense: true,
                  ),
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _isSendingMessage ? null : _sendMessage,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _isSendingMessage
                        ? AppColors.ai.withValues(alpha: 0.4)
                        : AppColors.ai,
                    shape: BoxShape.circle,
                  ),
                  child: _isSendingMessage
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: AppColors.bgDeep),
                          ),
                        )
                      : const Icon(CupertinoIcons.arrow_up,
                          size: 18, color: AppColors.bgDeep),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Frosted-glass action bar ──────────────────────────────────────────────

  Widget _buildActionBar(Map<String, dynamic> action, double bottomPad) {
    final rawOptions = action['options'] as List<dynamic>?;
    final options = rawOptions?.cast<String>() ?? ['approve', 'deny'];
    final question = action['question'] as String?;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF0000000),
            border: Border(
              top: BorderSide(
                color: AppColors.waiting.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
          ),
          padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPad + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Question as the primary element — no redundant "ACTION REQUIRED" label
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 10),
                    child: PulsingDot(color: AppColors.waiting, size: 6),
                  ),
                  Expanded(
                    child: Text(
                      question?.isNotEmpty == true
                          ? question!
                          : 'Waiting for your response',
                      style: AppText.ui(
                          size: 14,
                          weight: FontWeight.w500,
                          height: 1.45,
                          color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
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
                        Expanded(child: _buildOptionButton(rowOptions[i])),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ),
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
            onPressed: () => _respond(action, displayLabel: label),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: AppColors.bgDeep,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: AppColors.bgDeep))
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
          onPressed: () => _respond(action, displayLabel: label),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AppColors.textSecondary))
              : Text(label,
                  style: AppText.ui(size: 14, weight: FontWeight.w500)),
        ),
      ),
    );
  }
}

// ── Header widgets ─────────────────────────────────────────────────────────────

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.chevron_left,
                size: 17, color: AppColors.ai),
            const SizedBox(width: 2),
            Text('Sessions',
                style: AppText.ui(
                    size: 15, weight: FontWeight.w500, color: AppColors.ai)),
          ],
        ),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _HeaderAction(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(icon, size: 17, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final StatusPalette palette;
  final String status;
  final bool isLive;
  const _StatusBadge(
      {required this.palette, required this.status, required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(7),
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
              decoration:
                  BoxDecoration(color: palette.dot, shape: BoxShape.circle),
            ),
          const SizedBox(width: 7),
          Text(
            status.toUpperCase(),
            style: AppText.mono(
                size: 10,
                weight: FontWeight.w600,
                color: palette.text,
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}

// Elapsed time: plain text with icon, no border box
class _ElapsedChip extends StatelessWidget {
  final String label;
  const _ElapsedChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(CupertinoIcons.clock, size: 10, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(label, style: AppText.mono(size: 11, color: AppColors.textMuted)),
      ],
    );
  }
}

class _ScrollToBottomFab extends StatelessWidget {
  final VoidCallback onTap;
  const _ScrollToBottomFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(CupertinoIcons.chevron_down,
            size: 16, color: AppColors.textSecondary),
      ),
    );
  }
}

class _CopyableCommandBox extends StatelessWidget {
  final String command;
  const _CopyableCommandBox({required this.command});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: command));
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Command copied',
              style: AppText.ui(size: 13, color: AppColors.textPrimary)),
          backgroundColor: AppColors.bgElevated,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    letterSpacing: 0.2),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(CupertinoIcons.doc_on_clipboard,
                size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Chat message widgets ───────────────────────────────────────────────────────

// User input: amber left accent bar, right-padded, secondary color
class _UserMessage extends StatelessWidget {
  final String text;
  const _UserMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 48, 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 2,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: AppColors.ai.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: AppText.ui(
                  size: 13.5,
                  height: 1.65,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// AI output: no avatar badge, full-width markdown — the content speaks for itself
class _AiMessage extends StatelessWidget {
  final String text;
  const _AiMessage({required this.text});

  static final MarkdownStyleSheet _sheet = MarkdownStyleSheet(
    p: AppText.ui(size: 13.5, height: 1.72, color: AppColors.textPrimary),
    pPadding: const EdgeInsets.only(bottom: 8),

    h1: AppText.display(size: 20, weight: FontWeight.w700),
    h1Padding: const EdgeInsets.only(top: 16, bottom: 6),
    h2: AppText.display(size: 17, weight: FontWeight.w700),
    h2Padding: const EdgeInsets.only(top: 14, bottom: 6),
    h3: AppText.display(size: 15, weight: FontWeight.w600),
    h3Padding: const EdgeInsets.only(top: 10, bottom: 4),
    h4: AppText.ui(
        size: 14, weight: FontWeight.w600, color: AppColors.textPrimary),
    h4Padding: const EdgeInsets.only(top: 8, bottom: 4),

    code: AppText.mono(size: 12, color: AppColors.ai),
    codeblockDecoration: BoxDecoration(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    codeblockPadding: const EdgeInsets.all(14),

    blockquote:
        AppText.ui(size: 13, color: AppColors.textSecondary, height: 1.6),
    blockquoteDecoration: const BoxDecoration(
      border: Border(left: BorderSide(color: AppColors.textMuted, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),

    listBullet: AppText.ui(size: 13, color: AppColors.textMuted),
    listBulletPadding: const EdgeInsets.only(right: 8),
    listIndent: 16,

    horizontalRuleDecoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
    ),

    tableHead: AppText.mono(
        size: 11, weight: FontWeight.w600, color: AppColors.textSecondary),
    tableBody: AppText.mono(size: 11, color: AppColors.textPrimary),
    tableBorder: TableBorder.all(color: AppColors.border, width: 1),
    tableHeadAlign: TextAlign.left,

    strong: AppText.ui(
        size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary),
    em: AppText.ui(size: 13.5, color: AppColors.textSecondary)
        .copyWith(fontStyle: FontStyle.italic),

    blockSpacing: 4,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 8),
      child: MarkdownBody(
        data: text,
        styleSheet: _sheet,
        softLineBreak: true,
        selectable: true,
        builders: {'code': _CodeBlockBuilder()},
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  static String _lang(dynamic element) {
    try {
      final cls = (element.attributes as Map)['class'] as String? ?? '';
      if (cls.startsWith('language-')) return cls.substring(9).toLowerCase();
      return cls.toLowerCase();
    } catch (_) {
      return '';
    }
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    dynamic element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent as String? ?? '';
    final lang = _lang(element);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Language label + copy — the signature of a real dev tool
          Container(
            padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                Text(
                  lang.isNotEmpty ? lang : 'code',
                  style: AppText.mono(
                      size: 10,
                      color: AppColors.textMuted,
                      letterSpacing: 0.4),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: code.trimRight()));
                    HapticFeedback.lightImpact();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Icon(CupertinoIcons.doc_on_clipboard,
                        size: 13, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                code.trimRight(),
                style: AppText.mono(
                    size: 12, height: 1.6, color: AppColors.terminalText),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Waiting spinner ────────────────────────────────────────────────────────────

class _WaitingSpinner extends StatefulWidget {
  const _WaitingSpinner();

  @override
  State<_WaitingSpinner> createState() => _WaitingSpinnerState();
}

class _WaitingSpinnerState extends State<_WaitingSpinner>
    with SingleTickerProviderStateMixin {
  static const _verbs = [
    'Thinking',
    'Working',
    'Reading',
    'Writing',
    'Analyzing',
    'Planning',
    'Reasoning',
  ];

  int _index = 0;
  Timer? _timer;
  late AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: 1,
    );
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      _fade.reverse().then((_) {
        if (!mounted) return;
        setState(() => _index = (_index + 1) % _verbs.length);
        _fade.forward();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          const CupertinoActivityIndicator(color: AppColors.ai, radius: 7),
          const SizedBox(width: 10),
          FadeTransition(
            opacity: _fade,
            child: Text(
              '${_verbs[_index]}…',
              style: AppText.mono(size: 12, color: AppColors.ai),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats row widgets ──────────────────────────────────────────────────────────

class _StatSep extends StatelessWidget {
  const _StatSep();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      color: AppColors.borderSubtle,
    );
  }
}

class _AnimatedStatCell extends StatefulWidget {
  final int value;
  final String label;
  final Color color;
  final String Function(int) formatter;

  const _AnimatedStatCell({
    required this.value,
    required this.label,
    required this.color,
    required this.formatter,
  });

  @override
  State<_AnimatedStatCell> createState() => _AnimatedStatCellState();
}

class _AnimatedStatCellState extends State<_AnimatedStatCell>
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
        duration: const Duration(milliseconds: 700), vsync: this);
    _countAnim = _controller.drive(
      Tween<double>(begin: _fromValue, end: _fromValue)
          .chain(CurveTween(curve: Curves.easeOut)),
    );
    _glowAnim = _controller.drive(TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 70),
    ]));
  }

  @override
  void didUpdateWidget(_AnimatedStatCell old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _fromValue = _countAnim.value;
      _countAnim = _controller.drive(
        Tween<double>(begin: _fromValue, end: widget.value.toDouble())
            .chain(CurveTween(curve: Curves.easeOut)),
      );
      _glowAnim = _controller.drive(TweenSequence([
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 70),
      ]));
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
    return Expanded(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final displayed = _countAnim.value.round();
          final glow = _glowAnim.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.formatter(displayed),
                style: AppText.display(
                  size: 15,
                  color: glow > 0.01
                      ? Color.lerp(widget.color, Colors.white, glow * 0.25)!
                      : widget.color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: AppText.mono(
                    size: 9, color: AppColors.textMuted, letterSpacing: 0.5),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AnimatedCostCell extends StatefulWidget {
  final double value;
  final String Function(double) formatter;
  const _AnimatedCostCell({required this.value, required this.formatter});

  @override
  State<_AnimatedCostCell> createState() => _AnimatedCostCellState();
}

class _AnimatedCostCellState extends State<_AnimatedCostCell>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _countAnim;
  late Animation<double> _glowAnim;
  double _fromValue = 0;

  static const _color = Color(0xFF818CF8);

  @override
  void initState() {
    super.initState();
    _fromValue = widget.value;
    _controller = AnimationController(
        duration: const Duration(milliseconds: 900), vsync: this);
    _countAnim = _controller.drive(
      Tween<double>(begin: _fromValue, end: _fromValue)
          .chain(CurveTween(curve: Curves.easeOut)),
    );
    _glowAnim = _controller.drive(TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 75),
    ]));
  }

  @override
  void didUpdateWidget(_AnimatedCostCell old) {
    super.didUpdateWidget(old);
    if ((old.value - widget.value).abs() > 0.000001) {
      _fromValue = _countAnim.value;
      _countAnim = _controller.drive(
        Tween<double>(begin: _fromValue, end: widget.value)
            .chain(CurveTween(curve: Curves.easeOut)),
      );
      _glowAnim = _controller.drive(TweenSequence([
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 25),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 75),
      ]));
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
    return Expanded(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final glow = _glowAnim.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.formatter(_countAnim.value),
                style: AppText.display(
                  size: 15,
                  color: glow > 0.01
                      ? Color.lerp(_color, Colors.white, glow * 0.25)!
                      : _color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'cost',
                style: AppText.mono(
                    size: 9, color: AppColors.textMuted, letterSpacing: 0.5),
              ),
            ],
          );
        },
      ),
    );
  }
}
