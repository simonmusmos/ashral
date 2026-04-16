import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SessionCard extends StatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback onLeave;
  final Future<void> Function(String? customName) onRename;
  final VoidCallback? onTap;

  const SessionCard({
    super.key,
    required this.session,
    required this.onLeave,
    required this.onRename,
    this.onTap,
  });

  @override
  State<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<SessionCard> {
  bool _leaving = false;

  String _displayName() {
    final customName = widget.session['customName'] as String?;
    if (customName != null && customName.isNotEmpty) return customName;
    final name = widget.session['name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    return widget.session['sessionId'] as String? ??
        widget.session['id'] as String? ??
        '—';
  }

  String _status() {
    return (widget.session['status'] as String? ?? '').toLowerCase();
  }

  Future<void> _handleLeave() async {
    setState(() => _leaving = true);
    try {
      widget.onLeave();
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  Future<void> _handleRename() async {
    final current = widget.session['customName'] as String? ?? '';
    final controller = TextEditingController(text: current);

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: AppColors.border),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rename session',
              style: AppText.display(size: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'Leave empty to reset to the default name.',
              style: AppText.ui(size: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: AppText.ui(size: 14),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: Text('Cancel', style: AppText.ui(size: 14, weight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    child: Text('Save', style: AppText.ui(size: 14, weight: FontWeight.w600, color: AppColors.bgDeep)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (result == null) return;
    await widget.onRename(result.isEmpty ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.session['agent'] as String? ?? '';
    final status = _status();
    final isLive = AppStatus.isLive(status);
    final palette = status.isNotEmpty ? AppStatus.palette(status) : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap ?? _handleRename,
        overlayColor: WidgetStateProperty.all(
            AppColors.textPrimary.withValues(alpha: 0.03)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.borderSubtle),
              // Subtle left accent for live sessions
              left: isLive
                  ? const BorderSide(color: AppColors.running, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AgentBadge(agent: agent),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.ui(
                        size: 14,
                        weight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (agent.isNotEmpty) ...[
                          Text(
                            agent,
                            style: AppText.mono(
                              size: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                        if (palette != null) ...[
                          if (agent.isNotEmpty) const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: palette.bg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isLive)
                                  _PulsingDot(color: palette.dot, size: 5)
                                else
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: palette.dot,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                const SizedBox(width: 5),
                                Text(
                                  status,
                                  style: AppText.mono(
                                    size: 10,
                                    weight: FontWeight.w500,
                                    color: palette.text,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _leaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.textMuted,
                      ),
                    )
                  : GestureDetector(
                      onTap: _handleLeave,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 4),
                        child: Text(
                          'Leave',
                          style: AppText.ui(
                            size: 12,
                            weight: FontWeight.w500,
                            color: AppColors.error.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Agent badge ────────────────────────────────────────────────────────────────

class AgentBadge extends StatelessWidget {
  final String agent;
  final double size;

  const AgentBadge({super.key, required this.agent, this.size = 36});

  static String? _assetPath(String agent) {
    final n = agent.toLowerCase();
    if (n.contains('claude')) return 'assets/images/agents/claude.png';
    if (n.contains('codex') || n.contains('openai') || n.contains('gpt')) {
      return 'assets/images/agents/openai.png';
    }
    return null;
  }

  static ({Color bg, String label}) _fallback(String agent) {
    final n = agent.toLowerCase();
    if (n.contains('gemini') || n.contains('google')) {
      return (bg: const Color(0xFF4285F4), label: 'G');
    }
    if (n.contains('cursor')) return (bg: const Color(0xFF7C5CFC), label: 'Cur');
    if (n.contains('copilot') || n.contains('github')) {
      return (bg: const Color(0xFF2F81F7), label: 'GH');
    }
    if (n.contains('mistral')) return (bg: const Color(0xFFFF7000), label: 'M');
    if (n.contains('grok') || n.contains('xai')) {
      return (bg: const Color(0xFF1D9BF0), label: 'xAI');
    }
    final label = agent.isNotEmpty ? agent[0].toUpperCase() : '?';
    return (bg: AppColors.bgElevated, label: label);
  }

  @override
  Widget build(BuildContext context) {
    final path = _assetPath(agent);
    final radius = size * 0.28;
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        color: path != null ? AppColors.bgElevated : _fallback(agent).bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: path != null
          ? Image.asset(path, width: size, height: size, fit: BoxFit.contain)
          : Center(
              child: Text(
                _fallback(agent).label,
                style: AppText.mono(
                  size: _fallback(agent).label.length > 1 ? 9 : 13,
                  weight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
            ),
    );
  }
}

// ── Pulsing dot ────────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const _PulsingDot({required this.color, this.size = 6});

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
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
