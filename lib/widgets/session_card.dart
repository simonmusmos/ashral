import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'pulsing_dot.dart';

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
  bool _pressed = false;

  String _displayName() {
    final customName = widget.session['customName'] as String?;
    if (customName != null && customName.isNotEmpty) return customName;
    final name = widget.session['name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    return widget.session['sessionId'] as String? ??
        widget.session['id'] as String? ??
        '—';
  }

  String _status() =>
      (widget.session['status'] as String? ?? '').toLowerCase();

  Future<void> _handleLeave() async {
    HapticFeedback.lightImpact();
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AppColors.border),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 36,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 22),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Rename session', style: AppText.display(size: 18)),
            const SizedBox(height: 4),
            Text(
              'Leave empty to reset to the default name.',
              style: AppText.ui(size: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 22),
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
                    child: Text('Cancel',
                        style: AppText.ui(size: 14, weight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, controller.text.trim()),
                    child: Text('Save',
                        style: AppText.ui(
                            size: 14,
                            weight: FontWeight.w600,
                            color: AppColors.bgDeep)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (result == null) return;
    await widget.onRename(result.isEmpty ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.session['agent'] as String? ?? '';
    final status = _status();
    final isLive = AppStatus.isLive(status);
    final palette = status.isNotEmpty ? AppStatus.palette(status) : null;
    final isResumable =
        (widget.session['agentSessionId'] as String?)?.isNotEmpty == true;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap ?? _handleRename,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          decoration: BoxDecoration(
            color: isLive
                ? Color.lerp(AppColors.bgBase, AppColors.running, 0.04)!
                : AppColors.bgBase,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLive ? AppColors.runningBorder : AppColors.border,
            ),
            boxShadow: isLive
                ? [
                    BoxShadow(
                      color: AppColors.running.withValues(alpha: 0.10),
                      blurRadius: 24,
                      spreadRadius: -2,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AgentBadge(agent: agent, size: 40),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.display(
                                size: 16,
                                weight: isLive
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                if (agent.isNotEmpty)
                                  Text(
                                    agent,
                                    style: AppText.mono(
                                        size: 11,
                                        color: AppColors.textMuted),
                                  ),
                                if (palette != null) ...[
                                  if (agent.isNotEmpty)
                                    const SizedBox(width: 8),
                                  _StatusPill(
                                      palette: palette,
                                      status: status,
                                      isLive: isLive),
                                ],
                                if (isResumable) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    CupertinoIcons.arrow_counterclockwise,
                                    size: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 12),

                      _leaving
                          ? const SizedBox(
                              width: 32,
                              height: 32,
                              child: Center(
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CupertinoActivityIndicator(
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                            )
                          : GestureDetector(
                              onTap: _handleLeave,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppColors.borderSubtle),
                                ),
                                child: const Icon(
                                  CupertinoIcons.xmark,
                                  size: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Status pill ────────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final StatusPalette palette;
  final String status;
  final bool isLive;

  const _StatusPill({
    required this.palette,
    required this.status,
    required this.isLive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive)
            PulsingDot(color: palette.dot, size: 5)
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
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: path != null ? AppColors.bgElevated : _fallback(agent).bg,
        borderRadius: BorderRadius.circular(radius),
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
