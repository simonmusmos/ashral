import 'package:flutter/material.dart';

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
    return widget.session['sessionId'] as String? ?? widget.session['id'] as String? ?? '—';
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

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename session'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Custom name (leave empty to reset)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null) return; // cancelled
    // Empty string → clear custom name (fall back to default)
    await widget.onRename(result.isEmpty ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.session['agent'] as String? ?? '';
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(Icons.terminal,
              color: colorScheme.onPrimaryContainer, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _displayName(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 16, color: colorScheme.onSurface.withOpacity(0.4)),
              tooltip: 'Rename',
              visualDensity: VisualDensity.compact,
              onPressed: _handleRename,
            ),
          ],
        ),
        subtitle: agent.isNotEmpty
            ? Row(
                children: [
                  Icon(Icons.smart_toy_outlined,
                      size: 13, color: colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(agent,
                      style: TextStyle(
                          color: colorScheme.primary, fontSize: 12)),
                ],
              )
            : null,
        trailing: _leaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: _handleLeave,
                style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error),
                child: const Text('Leave'),
              ),
      ),
    );
  }
}
