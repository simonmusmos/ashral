import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/session_service.dart';
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
      final incoming =
          await SessionService.fetchSessionOutput(widget.sessionId);
      if (!mounted) return;

      bool added = false;
      for (final chunk in incoming) {
        final id = chunk['chunkId'] as String? ?? '';
        if (id.isNotEmpty && _seenIds.contains(id)) continue;
        if (id.isNotEmpty) _seenIds.add(id);
        _chunks.add(chunk);
        added = true;
      }

      setState(() {
        _initialLoading = false;
        _error = null;
      });

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

    // Schedule next poll
    _pollTimer?.cancel();
    _pollTimer = Timer(const Duration(seconds: 3), _poll);
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
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: const Color(0xFFF2F2F2))),
      backgroundColor: const Color(0xFF181818),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  // ── Status colors ──────────────────────────────────────────────────────────

  static ({Color dot, Color bg, Color text}) _statusColors(String status) {
    switch (status.toLowerCase()) {
      case 'running':
      case 'active':
        return (
          dot: const Color(0xFF22C55E),
          bg: const Color(0xFF0D2016),
          text: const Color(0xFF4ADE80),
        );
      case 'waiting_for_input':
      case 'waiting':
      case 'pending':
        return (
          dot: const Color(0xFFF59E0B),
          bg: const Color(0xFF1C1500),
          text: const Color(0xFFFBBF24),
        );
      case 'completed':
        return (
          dot: const Color(0xFF6B7280),
          bg: const Color(0xFF161616),
          text: const Color(0xFF9CA3AF),
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
          if (_chunks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 17),
              color: const Color(0xFF4A4A4A),
              tooltip: 'Copy all output',
              onPressed: _copyAll,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: const Color(0xFF4A4A4A),
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
          child: Divider(height: 1, color: Color(0xFF181818)),
        ),
      ),
      body: _initialLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF333333),
                strokeWidth: 1.5,
              ),
            )
          : _error != null && _chunks.isEmpty
              ? _buildError()
              : _buildOutput(),
      floatingActionButton: !_autoScroll && _chunks.isNotEmpty
          ? FloatingActionButton.small(
              onPressed: () {
                setState(() => _autoScroll = true);
                _scrollToBottom();
              },
              backgroundColor: const Color(0xFF1E1E1E),
              foregroundColor: const Color(0xFF9CA3AF),
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
                size: 36, color: Color(0xFF2A2A2A)),
            const SizedBox(height: 14),
            Text(
              'Could not load output',
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
              onPressed: () {
                _pollTimer?.cancel();
                setState(() {
                  _initialLoading = true;
                  _error = null;
                });
                _poll();
              },
              child: Text('Try again',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w500)),
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
          child: _chunks.isEmpty
              ? _buildEmptyState()
              : _buildTerminal(),
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    final colors = _statusColors(_status);
    final isLive = _status == 'running' || _status == 'active';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF141414))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.dot.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLive)
                  _PulsingDot(color: colors.dot)
                else
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
                  _status,
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
          const Spacer(),
          Text(
            '${_chunks.length} chunks',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 10,
              color: const Color(0xFF2A2A2A),
            ),
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
          style: GoogleFonts.ibmPlexMono(
            fontSize: 11.5,
            height: 1.55,
            color: isStderr
                ? const Color(0xFFF87171)
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
      return const Color(0xFFF87171);
    }
    if (l.startsWith('warn') ||
        l.startsWith('Warn') ||
        l.startsWith('WARN') ||
        l.startsWith('⚠')) {
      return const Color(0xFFFBBF24);
    }
    if (l.startsWith(r'$') || l.startsWith('>') || l.startsWith('#')) {
      return const Color(0xFF7DD3FC);
    }
    if (l.startsWith('✓') ||
        l.startsWith('✔') ||
        l.startsWith('Done') ||
        l.startsWith('SUCCESS') ||
        l.startsWith('Completed')) {
      return const Color(0xFF4ADE80);
    }
    return const Color(0xFF8B8B8B);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.terminal_rounded, size: 28, color: Color(0xFF222222)),
          const SizedBox(height: 12),
          Text(
            'No output yet',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: const Color(0xFF383838)),
          ),
          const SizedBox(height: 4),
          Text(
            'Polling every 3 seconds…',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: const Color(0xFF2A2A2A)),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing dot for live status ────────────────────────────────────────────

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
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
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
