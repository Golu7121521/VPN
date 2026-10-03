import 'package:flutter/material.dart';

import '../core/theme.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});
  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  int _plan = 1;
  static const _features = [
    'Ad-free listening',
    'Unlimited skips',
    'High-quality audio',
    'Offline downloads',
    'Unlimited playlists',
    'Synced lyrics',
    'Exclusive content',
  ];
  static const _plans = [('Monthly', '₹119', 'per month'), ('Yearly', '₹999', 'save 30%')];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(24)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.workspace_premium_rounded, size: 48),
            SizedBox(height: 12),
            Text('Unlock Your Music', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('Go premium for the best listening experience.'),
          ]),
        ),
        const SizedBox(height: 20),
        for (final f in _features)
          ListTile(
            dense: true,
            leading: const Icon(Icons.check_circle_rounded, color: AppColors.primary),
            title: Text(f),
          ),
        const SizedBox(height: 12),
        Row(children: [
          for (var i = 0; i < _plans.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 0 ? 12 : 0),
                child: Semantics(
                  button: true,
                  selected: _plan == i,
                  label: '${_plans[i].$1} plan ${_plans[i].$2}',
                  child: GestureDetector(
                    onTap: () => setState(() => _plan = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _plan == i ? AppColors.primary : Colors.transparent, width: 2),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_plans[i].$1, style: const TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(_plans[i].$2, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                        Text(_plans[i].$3, style: const TextStyle(color: AppColors.primary, fontSize: 12)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Payments are not connected yet'))),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: const StadiumBorder()),
          child: const Text('Start Premium', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
