import 'package:flutter/material.dart';

import '../services/usage_service.dart';
import '../theme/app_theme.dart';

class UsageBar extends StatefulWidget {
  const UsageBar({super.key});

  @override
  State<UsageBar> createState() => _UsageBarState();
}

class _UsageBarState extends State<UsageBar> {
  UsageSummary? _summary;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await UsageService.getSummary();
    if (mounted) setState(() => _summary = s);
  }

  Future<void> _editLimits() async {
    final limits = UsageService.currentLimits;
    final dailyCtrl  = TextEditingController(text: limits.daily.toStringAsFixed(2));
    final weeklyCtrl = TextEditingController(text: limits.weekly.toStringAsFixed(2));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AppColors.border),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Spending limits', style: AppText.display(size: 18)),
            const SizedBox(height: 4),
            Text(
              'Set your daily and weekly budget caps (USD).',
              style: AppText.ui(size: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            _LimitField(label: 'Daily limit (\$)', controller: dailyCtrl),
            const SizedBox(height: 12),
            _LimitField(label: 'Weekly limit (\$)', controller: weeklyCtrl),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Cancel', style: AppText.ui(size: 14, weight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      final d = double.tryParse(dailyCtrl.text.trim()) ?? limits.daily;
                      final w = double.tryParse(weeklyCtrl.text.trim()) ?? limits.weekly;
                      await UsageService.setLimits(UsageLimits(daily: d, weekly: w));
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text('Save', style: AppText.ui(size: 14, weight: FontWeight.w600, color: AppColors.bgDeep)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 400), dailyCtrl.dispose);
    Future.delayed(const Duration(milliseconds: 400), weeklyCtrl.dispose);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    if (s == null) return const SizedBox.shrink();

    // Only show the widget if there's any tracked spending or limits differ from default
    final hasSpending = s.dailySpent > 0 || s.weeklySpent > 0;
    if (!hasSpending) return _buildEmpty();

    return _buildCard(s);
  }

  Widget _buildEmpty() {
    return GestureDetector(
      onTap: _editLimits,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgBase,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                size: 15, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Text(
              'No spending yet — tap to set limits',
              style: AppText.ui(size: 12, color: AppColors.textMuted),
            ),
            const Spacer(),
            const Icon(Icons.tune_rounded, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(UsageSummary s) {
    return GestureDetector(
      onTap: _editLimits,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgBase,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('USAGE', style: AppText.sectionLabel()),
                const Spacer(),
                const Icon(Icons.tune_rounded, size: 13, color: AppColors.textMuted),
              ],
            ),
            const SizedBox(height: 12),
            _UsageRow(
              label: 'Daily',
              spent: s.dailySpent,
              limit: s.limits.daily,
              pct: s.dailyPct,
            ),
            const SizedBox(height: 10),
            _UsageRow(
              label: 'Weekly',
              spent: s.weeklySpent,
              limit: s.limits.weekly,
              pct: s.weeklyPct,
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  final String label;
  final double spent;
  final double limit;
  final double pct;

  const _UsageRow({
    required this.label,
    required this.spent,
    required this.limit,
    required this.pct,
  });

  Color get _barColor {
    if (pct >= 0.9) return AppColors.error;
    if (pct >= 0.7) return AppColors.waiting;
    return AppColors.running;
  }

  @override
  Widget build(BuildContext context) {
    final pctLabel = '${(pct * 100).toStringAsFixed(0)}%';
    final spentLabel = '\$${spent.toStringAsFixed(3)}';
    final limitLabel = '\$${limit.toStringAsFixed(2)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppText.ui(size: 12, weight: FontWeight.w500, color: AppColors.textSecondary)),
            const Spacer(),
            Text(
              '$spentLabel / $limitLabel',
              style: AppText.mono(size: 10, color: AppColors.textMuted),
            ),
            const SizedBox(width: 8),
            Container(
              width: 38,
              alignment: Alignment.centerRight,
              child: Text(
                pctLabel,
                style: AppText.mono(
                  size: 11,
                  weight: FontWeight.w600,
                  color: _barColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (_, value, __) => LinearProgressIndicator(
              value: value,
              minHeight: 4,
              backgroundColor: AppColors.bgElevated,
              valueColor: AlwaysStoppedAnimation(_barColor),
            ),
          ),
        ),
      ],
    );
  }
}

class _LimitField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _LimitField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.ui(size: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppText.ui(size: 14),
        ),
      ],
    );
  }
}
