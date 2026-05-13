import 'package:flutter/cupertino.dart';

import '../services/session_service.dart';
import '../theme/app_theme.dart';

class FileDiffsSheet extends StatefulWidget {
  final String sessionId;
  const FileDiffsSheet({super.key, required this.sessionId});

  @override
  State<FileDiffsSheet> createState() => _FileDiffsSheetState();
}

class _FileDiffsSheetState extends State<FileDiffsSheet> {
  List<Map<String, dynamic>> _diffs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final diffs =
          await SessionService.fetchSessionDiffs(widget.sessionId);
      if (mounted) setState(() { _diffs = diffs; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgBase,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                children: [
                  Text('Files changed', style: AppText.display(size: 17)),
                  const Spacer(),
                  if (!_loading && _diffs.isNotEmpty)
                    Text(
                      '${_diffs.length}',
                      style: AppText.mono(
                          size: 12, color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
            Container(height: 0.5, color: AppColors.borderSubtle),
            // Body
            Expanded(
              child: _loading
                  ? const Center(
                      child: CupertinoActivityIndicator(
                          color: AppColors.textMuted))
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: AppText.ui(
                                  size: 13, color: AppColors.textMuted)))
                      : _diffs.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(CupertinoIcons.doc,
                                      size: 28, color: AppColors.textMuted),
                                  const SizedBox(height: 12),
                                  Text('No file changes yet',
                                      style: AppText.ui(
                                          size: 14,
                                          color: AppColors.textMuted)),
                                ],
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: EdgeInsets.only(
                                  bottom:
                                      MediaQuery.of(ctx).padding.bottom + 24),
                              itemCount: _diffs.length,
                              separatorBuilder: (_, __) => Container(
                                  height: 0.5,
                                  color: AppColors.borderSubtle),
                              itemBuilder: (_, i) {
                                // Newest first
                                final diff =
                                    _diffs[_diffs.length - 1 - i];
                                return _DiffTile(diff: diff);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Diff tile ──────────────────────────────────────────────────────────────────

class _DiffTile extends StatefulWidget {
  final Map<String, dynamic> diff;
  const _DiffTile({required this.diff});

  @override
  State<_DiffTile> createState() => _DiffTileState();
}

class _DiffTileState extends State<_DiffTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final path = widget.diff['path'] as String? ?? '';
    final type = widget.diff['type'] as String? ?? '';
    final oldStr = widget.diff['oldStr'] as String?;
    final newStr = widget.diff['newStr'] as String? ?? '';

    final lastSlash = path.lastIndexOf('/');
    final filename = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
    final dir = lastSlash > 0 ? path.substring(0, lastSlash) : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _TypeBadge(type: type),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        filename,
                        style: AppText.mono(
                          size: 13,
                          weight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (dir.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          dir,
                          style: AppText.mono(
                              size: 11, color: AppColors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 13,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) _DiffBody(oldStr: oldStr, newStr: newStr, type: type),
      ],
    );
  }
}

// ── Type badge ─────────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (type) {
      case 'str_replace':
        label = 'edit';
        color = AppColors.active;
      case 'create_file':
        label = 'new';
        color = AppColors.running;
      case 'write_file':
        label = 'write';
        color = AppColors.waiting;
      default:
        label = '~';
        color = AppColors.textMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppText.mono(
            size: 10, weight: FontWeight.w600, color: color),
      ),
    );
  }
}

// ── Diff body ──────────────────────────────────────────────────────────────────

class _DiffBody extends StatelessWidget {
  final String? oldStr;
  final String newStr;
  final String type;

  const _DiffBody(
      {required this.oldStr, required this.newStr, required this.type});

  @override
  Widget build(BuildContext context) {
    final oldLines =
        (oldStr?.isNotEmpty == true) ? oldStr!.split('\n') : <String>[];
    final newLines = newStr.split('\n');

    return Container(
      color: AppColors.bgDeep,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (oldLines.isNotEmpty) ...[
                for (final line in oldLines)
                  _DiffLine(prefix: '-', text: line, removed: true),
                const SizedBox(height: 3),
              ],
              for (final line in newLines)
                _DiffLine(prefix: '+', text: line, removed: false),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Diff line ──────────────────────────────────────────────────────────────────

class _DiffLine extends StatelessWidget {
  final String prefix;
  final String text;
  final bool removed;

  const _DiffLine(
      {required this.prefix, required this.text, required this.removed});

  @override
  Widget build(BuildContext context) {
    final color = removed ? AppColors.error : AppColors.running;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 1),
      color: color.withValues(alpha: 0.07),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 14,
            child: Text(
              prefix,
              style: AppText.mono(
                  size: 12, weight: FontWeight.w700, color: color),
            ),
          ),
          Text(
            text,
            style: AppText.mono(
                size: 12, color: color.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }
}
