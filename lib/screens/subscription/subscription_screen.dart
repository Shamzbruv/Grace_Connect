import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/subscription_provider.dart';
import '../../widgets/app_bottom_menu.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final subscriptionProvider = Provider.of<SubscriptionProvider>(context);
    final isSubscribed = subscriptionProvider.isPremium;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Amazing Grace Subscription',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const AppBottomMenu(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unlock Amazing Grace!',
              style: GoogleFonts.poppins(
                  fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'For just \$4.99/month, get access to the Interactive Bible, ad-free experience, exclusive devotionals, streak multipliers, and more premium features coming soon!',
              style: GoogleFonts.poppins(fontSize: 16),
            ),
            const SizedBox(height: 24),
            TextField(
              decoration: const InputDecoration(labelText: 'Card Number'),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(labelText: 'Expiry Date'),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(labelText: 'CVV'),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: (isSubscribed || subscriptionProvider.isLoading)
                  ? null
                  : () async {
                      try {
                        await subscriptionProvider.subscribe();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Subscribed to Amazing Grace! 🎉')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Failed to subscribe. Try again.')),
                          );
                        }
                      }
                    },
              icon: subscriptionProvider.isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_open),
              label: Text(subscriptionProvider.isLoading
                  ? 'Processing...'
                  : 'Subscribe Now - \$4.99/month'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            if (isSubscribed)
              const Padding(
                padding: EdgeInsets.only(top: 16.0),
                child: Text(
                  'You are subscribed to Amazing Grace! Enjoy premium features. 🎉',
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
