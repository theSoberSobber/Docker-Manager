import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../data/services/subscription_service.dart';

/// Unified card showing app info + Pro subscription status.
///
/// When Pro: gold gradient, "Docker Manager Pro", version, Rate, GitHub, Manage Sub.
/// When free: normal card, benefits, Subscribe/Restore, FOSS message.
class ProCard extends StatefulWidget {
  final String appVersion;
  final String buildNumber;
  final VoidCallback onOpenGitHub;
  final VoidCallback onRatePlayStore;

  const ProCard({
    super.key,
    required this.appVersion,
    required this.buildNumber,
    required this.onOpenGitHub,
    required this.onRatePlayStore,
  });

  @override
  State<ProCard> createState() => _ProCardState();
}

class _ProCardState extends State<ProCard> {
  final SubscriptionService _subscriptionService = SubscriptionService();
  bool _isLoading = false;

  Future<void> _handleSubscribe() async {
    setState(() => _isLoading = true);

    final success = await _subscriptionService.showPaywall(context);

    if (mounted) {
      setState(() => _isLoading = false);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text('pro.purchase_success'.tr()),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _handleRestore() async {
    setState(() => _isLoading = true);

    final success = await _subscriptionService.restorePurchases();

    if (mounted) {
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.info_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(success
                    ? 'pro.restore_success'.tr()
                    : 'pro.restore_no_purchases'.tr()),
              ),
            ],
          ),
          backgroundColor: success ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Future<void> _handleManage() async {
    await _subscriptionService.showCustomerCenter(context);
  }

  void _sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'pavitchhabra1611@gmail.com',
      query: 'subject=Docker Manager Pro - Request Code',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPro = _subscriptionService.isPro;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final versionText = (widget.appVersion.isNotEmpty && widget.buildNumber.isNotEmpty)
        ? 'settings.version_label'.tr(args: [widget.appVersion, widget.buildNumber])
        : 'settings.version_loading'.tr();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: isPro ? 2 : 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isPro
              ? BorderSide(
                  color: isDark ? Colors.amber.shade600 : Colors.amber.shade400,
                  width: 1.5,
                )
              : BorderSide.none,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: isPro
                ? LinearGradient(
                    colors: isDark
                        ? [Colors.amber.shade900.withOpacity(0.3), Colors.orange.shade900.withOpacity(0.3)]
                        : [Colors.amber.shade50, Colors.orange.shade50],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: icon + title + GitHub icon
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isPro
                            ? (isDark ? Colors.amber.shade800.withOpacity(0.4) : Colors.amber.shade100)
                            : colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isPro ? Icons.workspace_premium : Icons.rocket_launch,
                        color: isPro
                            ? (isDark ? Colors.amber.shade300 : Colors.amber.shade700)
                            : colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPro ? 'Docker Manager Pro' : 'Docker Manager',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            versionText,
                            style: TextStyle(
                              fontSize: 12,
                              color: isPro
                                  ? (isDark ? Colors.amber.shade300 : Colors.amber.shade700)
                                  : colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isPro)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade400,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'PRO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    IconButton(
                      icon: const FaIcon(FontAwesomeIcons.github, size: 20),
                      tooltip: 'settings.github_repo'.tr(),
                      onPressed: widget.onOpenGitHub,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Rate on Play + Manage Subscription row
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.play_circle, size: 18),
                      label: Text('settings.rate_play'.tr()),
                      onPressed: widget.onRatePlayStore,
                      style: isPro
                          ? FilledButton.styleFrom(
                              backgroundColor: isDark ? Colors.amber.shade700 : Colors.amber.shade600,
                              foregroundColor: Colors.white,
                            )
                          : null,
                    ),
                    if (isPro)
                      OutlinedButton.icon(
                        onPressed: _handleManage,
                        icon: const Icon(Icons.manage_accounts, size: 18),
                        label: Text('pro.manage'.tr()),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.amber.shade300 : Colors.amber.shade700,
                          side: BorderSide(color: isDark ? Colors.amber.shade600 : Colors.amber.shade400),
                        ),
                      ),
                  ],
                ),

                // Non-Pro: benefits + subscribe/restore + FOSS
                if (!isPro) ...[
                  const SizedBox(height: 12),
                  Text(
                    'pro.description'.tr(),
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildBenefit(Icons.notifications_active, 'pro.benefit_alerts'.tr()),
                  const SizedBox(height: 6),
                  _buildBenefit(Icons.dns, 'pro.benefit_multi_server'.tr()),
                  const SizedBox(height: 6),
                  _buildBenefit(Icons.favorite, 'pro.benefit_support'.tr()),
                  const SizedBox(height: 16),

                  // Subscribe + Restore
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: FilledButton.icon(
                          onPressed: _isLoading ? null : _handleSubscribe,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.rocket_launch, size: 18),
                          label: Text('pro.subscribe'.tr()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : _handleRestore,
                          child: Text(
                            'pro.restore'.tr(),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // FOSS-friendly message
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.favorite_border,
                          size: 16,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'pro.foss_message'.tr(),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: _sendEmail,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.email_outlined,
                                  size: 14,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'pro.email_me'.tr(),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBenefit(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}
