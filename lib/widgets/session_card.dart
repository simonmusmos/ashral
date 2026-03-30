import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SessionCard extends StatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback onLeave;
  final Future<void> Function(String? customName) onRename;

  const SessionCard({
    super.key,
    required this.session,
    required this.onLeave,
    required this.onRename,
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
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: Color(0xFF222222)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rename session',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFF2F2F2),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Leave empty to reset to the default name.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: const Color(0xFF4A4A4A)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: const Color(0xFFF2F2F2)),
              decoration: InputDecoration(
                hintText: 'Session name…',
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14, color: const Color(0xFF333333)),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF222222)),
                      foregroundColor: const Color(0xFF5C5C5C),
                    ),
                    child: Text('Cancel',
                        style:
                            GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(ctx, controller.text.trim()),
                    child: Text('Save',
                        style:
                            GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
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

    return InkWell(
      onTap: _handleRename,
      overlayColor: WidgetStateProperty.all(
          const Color(0xFFF2F2F2).withValues(alpha: 0.03)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFF141414)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Agent logo badge
            _AgentBadge(agent: agent),

            // Session info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFE8E8E8),
                    ),
                  ),
                  if (agent.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      agent,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 11,
                        color: const Color(0xFF3A3A3A),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Leave action
            const SizedBox(width: 16),
            _leaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Color(0xFF333333),
                    ),
                  )
                : GestureDetector(
                    onTap: _handleLeave,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 2),
                      child: Text(
                        'Leave',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _AgentBadge extends StatelessWidget {
  final String agent;

  const _AgentBadge({required this.agent});

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
    return (bg: const Color(0xFF2A2A2A), label: label);
  }

  @override
  Widget build(BuildContext context) {
    final path = _assetPath(agent);
    return Container(
      width: 30,
      height: 30,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        color: path != null ? Colors.transparent : _fallback(agent).bg,
        borderRadius: BorderRadius.circular(7),
      ),
      clipBehavior: Clip.antiAlias,
      child: path != null
          ? Image.asset(path, width: 30, height: 30, fit: BoxFit.contain)
          : Center(
              child: Text(
                _fallback(agent).label,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: _fallback(agent).label.length > 1 ? 9 : 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
            ),
    );
  }
}
