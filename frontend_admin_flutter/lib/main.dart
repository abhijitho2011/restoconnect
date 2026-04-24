import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api',
);

final initialTokenProvider = Provider<String?>((ref) => null);
final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(initialTokenProvider));
});
final apiProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(authProvider).token),
);

final analyticsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  return ref.watch(apiProvider).getMap('/restaurants/analytics');
});

final restaurantsProvider = FutureProvider.autoDispose<List<dynamic>>((
  ref,
) async {
  return ref.watch(apiProvider).getList('/restaurants');
});

final plansProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.watch(apiProvider).getList('/restaurants/subscription-plans');
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        initialTokenProvider.overrideWithValue(prefs.getString('accessToken')),
      ],
      child: const AdminApp(),
    ),
  );
}

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter(
      initialLocation: ref.watch(authProvider).isAuthenticated ? '/' : '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) => const AdminDashboardScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'RestoConnect Admin',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        visualDensity: VisualDensity.standard,
      ),
      routerConfig: router,
    );
  }
}

class ApiClient {
  ApiClient(this.token);

  final String? token;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http.patch(
      Uri.parse('$apiBaseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> getMap(String path) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl$path'),
      headers: _headers,
    );
    return _decodeMap(response);
  }

  Future<List<dynamic>> getList(String path) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl$path'),
      headers: _headers,
    );
    final decoded = _decode(response);
    if (decoded is List<dynamic>) return decoded;
    throw ApiException('Expected a list response.');
  }

  dynamic _decode(http.Response response) {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    final message = body is Map<String, dynamic>
        ? body['message']?.toString()
        : null;
    throw ApiException(
      message ?? 'Request failed with status ${response.statusCode}.',
    );
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    final decoded = _decode(response);
    if (decoded is Map<String, dynamic>) return decoded;
    throw ApiException('Expected an object response.');
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthState {
  const AuthState({this.token, this.loading = false});
  final String? token;
  final bool loading;
  bool get isAuthenticated => token != null && token!.isNotEmpty;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(String? initialToken) : super(AuthState(token: initialToken));

  Future<String?> sendOtp(String phone) async {
    state = AuthState(token: state.token, loading: true);
    try {
      final api = ApiClient(null);
      final response = await api.post('/auth/send-otp', {
        'phone': phone,
        'role': 'SUPER_ADMIN',
      });
      return response['devOtp']?.toString();
    } finally {
      state = AuthState(token: state.token);
    }
  }

  Future<void> verifyOtp(String phone, String otp) async {
    state = AuthState(token: state.token, loading: true);
    try {
      final api = ApiClient(null);
      final response = await api.post('/auth/verify-otp', {
        'phone': phone,
        'otp': otp,
        'role': 'SUPER_ADMIN',
      });
      final token = response['accessToken'].toString();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('accessToken', token);
      state = AuthState(token: token);
    } finally {
      if (state.loading) state = AuthState(token: state.token);
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    state = const AuthState();
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final phoneController = TextEditingController(text: '+919999999999');
  final otpController = TextEditingController();
  String? devOtp;

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'RestoConnect Admin',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Mobile number',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: auth.loading ? null : _sendOtp,
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Send OTP'),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: otpController,
                    decoration: const InputDecoration(labelText: 'OTP'),
                  ),
                  if (devOtp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Development OTP: $devOtp',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: auth.loading ? null : _verifyOtp,
                    child: auth.loading
                        ? const LinearProgressIndicator()
                        : const Text('Verify and continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendOtp() async {
    try {
      final otp = await ref
          .read(authProvider.notifier)
          .sendOtp(phoneController.text.trim());
      setState(() => devOtp = otp);
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _verifyOtp() async {
    try {
      await ref
          .read(authProvider.notifier)
          .verifyOtp(phoneController.text.trim(), otpController.text.trim());
      if (mounted) context.go('/');
    } on Object catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(authProvider).isAuthenticated) {
      return const LoginScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(analyticsProvider);
              ref.invalidate(restaurantsProvider);
              ref.invalidate(plansProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const CreateRestaurantDialog(),
        ),
        icon: const Icon(Icons.add_business),
        label: const Text('Restaurant'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          AnalyticsStrip(),
          SizedBox(height: 24),
          RestaurantsSection(),
          SizedBox(height: 24),
          PlansSection(),
        ],
      ),
    );
  }
}

class AnalyticsStrip extends ConsumerWidget {
  const AnalyticsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider);
    return analytics.when(
      data: (data) => Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          MetricCard(
            label: 'Restaurants',
            value: '${data['restaurants'] ?? 0}',
            icon: Icons.storefront,
          ),
          MetricCard(
            label: 'Orders',
            value: '${data['orders'] ?? 0}',
            icon: Icons.receipt_long,
          ),
          MetricCard(
            label: 'Revenue',
            value: currency(data['revenue']),
            icon: Icons.currency_rupee,
          ),
        ],
      ),
      error: (error, stack) => ErrorPanel(message: error.toString()),
      loading: () => const LinearProgressIndicator(),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RestaurantsSection extends ConsumerWidget {
  const RestaurantsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurants = ref.watch(restaurantsProvider);
    return Section(
      title: 'Restaurants',
      child: restaurants.when(
        data: (rows) => Column(
          children: rows
              .map(
                (raw) =>
                    RestaurantTile(restaurant: raw as Map<String, dynamic>),
              )
              .toList(),
        ),
        error: (error, stack) => ErrorPanel(message: error.toString()),
        loading: () => const LinearProgressIndicator(),
      ),
    );
  }
}

class RestaurantTile extends ConsumerWidget {
  const RestaurantTile({required this.restaurant, super.key});

  final Map<String, dynamic> restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = restaurant['status']?.toString() ?? 'PENDING';
    return Card(
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(
          child: Text((restaurant['name']?.toString() ?? 'R').characters.first),
        ),
        title: Text(restaurant['name']?.toString() ?? 'Restaurant'),
        subtitle: Text(
          '${restaurant['subscriptionPlan'] ?? 'No plan'} • ${restaurant['_count']?['orders'] ?? 0} orders',
        ),
        trailing: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(label: Text(status)),
            IconButton(
              tooltip: 'Approve',
              onPressed: status == 'APPROVED'
                  ? null
                  : () => _setStatus(
                      ref,
                      restaurant['id'].toString(),
                      'APPROVED',
                    ),
              icon: const Icon(Icons.check_circle_outline),
            ),
            IconButton(
              tooltip: 'Disable',
              onPressed: status == 'DISABLED'
                  ? null
                  : () => _setStatus(
                      ref,
                      restaurant['id'].toString(),
                      'DISABLED',
                    ),
              icon: const Icon(Icons.block),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setStatus(WidgetRef ref, String id, String status) async {
    await ref.read(apiProvider).patch('/restaurants/$id/status', {
      'status': status,
    });
    ref.invalidate(restaurantsProvider);
  }
}

class PlansSection extends ConsumerWidget {
  const PlansSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    return Section(
      title: 'Subscription Plans',
      trailing: FilledButton.icon(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const CreatePlanDialog(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Plan'),
      ),
      child: plans.when(
        data: (rows) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: rows.map((raw) {
            final plan = raw as Map<String, dynamic>;
            return SizedBox(
              width: 280,
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan['name'].toString(),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(currency((plan['monthlyPricePaise'] as num) / 100)),
                      Text((plan['features'] as List<dynamic>).join(', ')),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        error: (error, stack) => ErrorPanel(message: error.toString()),
        loading: () => const LinearProgressIndicator(),
      ),
    );
  }
}

class CreateRestaurantDialog extends ConsumerStatefulWidget {
  const CreateRestaurantDialog({super.key});

  @override
  ConsumerState<CreateRestaurantDialog> createState() =>
      _CreateRestaurantDialogState();
}

class _CreateRestaurantDialogState
    extends ConsumerState<CreateRestaurantDialog> {
  final name = TextEditingController();
  final ownerPhone = TextEditingController();
  final plan = TextEditingController(text: 'STARTER');

  @override
  void dispose() {
    name.dispose();
    ownerPhone.dispose();
    plan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create restaurant'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: ownerPhone,
              decoration: const InputDecoration(labelText: 'Owner mobile'),
            ),
            TextField(
              controller: plan,
              decoration: const InputDecoration(
                labelText: 'Subscription plan code',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }

  Future<void> _submit() async {
    await ref.read(apiProvider).post('/restaurants', {
      'name': name.text.trim(),
      'ownerPhone': ownerPhone.text.trim().isEmpty
          ? null
          : ownerPhone.text.trim(),
      'subscriptionPlan': plan.text.trim(),
    });
    ref.invalidate(restaurantsProvider);
    if (mounted) Navigator.pop(context);
  }
}

class CreatePlanDialog extends ConsumerStatefulWidget {
  const CreatePlanDialog({super.key});

  @override
  ConsumerState<CreatePlanDialog> createState() => _CreatePlanDialogState();
}

class _CreatePlanDialogState extends ConsumerState<CreatePlanDialog> {
  final code = TextEditingController();
  final name = TextEditingController();
  final price = TextEditingController();
  final features = TextEditingController();

  @override
  void dispose() {
    code.dispose();
    name.dispose();
    price.dispose();
    features.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create plan'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: 'Code'),
            ),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: price,
              decoration: const InputDecoration(
                labelText: 'Monthly price in paise',
              ),
            ),
            TextField(
              controller: features,
              decoration: const InputDecoration(
                labelText: 'Features, comma separated',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  Future<void> _submit() async {
    await ref.read(apiProvider).post('/restaurants/subscription-plans', {
      'code': code.text.trim(),
      'name': name.text.trim(),
      'monthlyPricePaise': int.parse(price.text.trim()),
      'features': features.text
          .split(',')
          .map((feature) => feature.trim())
          .where((feature) => feature.isNotEmpty)
          .toList(),
    });
    ref.invalidate(plansProvider);
    if (mounted) Navigator.pop(context);
  }
}

class Section extends StatelessWidget {
  const Section({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

String currency(dynamic value) {
  final amount = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(amount);
}
