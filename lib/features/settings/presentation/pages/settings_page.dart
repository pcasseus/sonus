import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../account/application/controllers/account_controller.dart';
import '../../../analytics/presentation/pages/listening_history_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AccountController?>();

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _AccountCard(controller: controller),
          const SizedBox(height: 24),
          Text('Listening', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const _ListeningCard(),
        ],
      ),
    );
  }
}

class _ListeningCard extends StatelessWidget {
  const _ListeningCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        key: const ValueKey<String>('settings-listening-history'),
        leading: const Icon(Icons.history_rounded),
        title: const Text('Listening history'),
        subtitle: const Text(
          'Review your listening sessions and qualified streams.',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => const ListeningHistoryPage(),
            ),
          );
        },
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.controller});

  final AccountController? controller;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;

    if (controller == null) {
      return const Card(
        child: ListTile(
          key: ValueKey<String>('settings-account-unavailable'),
          leading: Icon(Icons.account_circle_outlined),
          title: Text('Google account'),
          subtitle: Text('Account sign-in is not configured for this build.'),
        ),
      );
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        if (controller.isSignedIn) {
          return _SignedInAccountCard(controller: controller);
        }

        return _SignedOutAccountCard(controller: controller);
      },
    );
  }
}

class _SignedOutAccountCard extends StatelessWidget {
  const _SignedOutAccountCard({required this.controller});

  final AccountController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey<String>('settings-account-signed-out'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_circle_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Google account',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Sign in to connect your Sonus account.'),
            if (controller.hasError) ...[
              const SizedBox(height: 12),
              Text(
                'Sign-in failed. Please try again.',
                key: const ValueKey<String>('settings-account-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey<String>('settings-google-sign-in-button'),
              onPressed: controller.isLoading
                  ? null
                  : controller.signInWithGoogle,
              icon: controller.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded),
              label: Text(
                controller.isLoading ? 'Signing in...' : 'Sign in with Google',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedInAccountCard extends StatelessWidget {
  const _SignedInAccountCard({required this.controller});

  final AccountController controller;

  @override
  Widget build(BuildContext context) {
    final user = controller.user!;

    final displayName = user.displayName ?? user.email ?? 'Google account';
    final secondaryText = user.displayName != null && user.email != null
        ? user.email
        : null;

    return Card(
      key: const ValueKey<String>('settings-account-signed-in'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _AccountAvatar(avatarUrl: user.avatarUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        key: const ValueKey<String>(
                          'settings-account-display-name',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (secondaryText != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          secondaryText,
                          key: const ValueKey<String>('settings-account-email'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (controller.hasError) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Account action failed. Please try again.',
                  key: const ValueKey<String>('settings-account-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('settings-sign-out-button'),
                onPressed: controller.isLoading ? null : controller.signOut,
                icon: controller.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded),
                label: Text(
                  controller.isLoading ? 'Signing out...' : 'Sign out',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = this.avatarUrl;

    return CircleAvatar(
      key: const ValueKey<String>('settings-account-avatar'),
      foregroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
      child: avatarUrl == null ? const Icon(Icons.person_rounded) : null,
    );
  }
}
