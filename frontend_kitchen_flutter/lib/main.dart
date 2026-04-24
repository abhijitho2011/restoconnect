import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api',
);
const socketUrl = String.fromEnvironment(
  'SOCKET_URL',
  defaultValue: 'http://localhost:3000',
);

final initialSessionProvider = Provider<AuthState>((ref) => const AuthState());
final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(initialSessionProvider));
});
final apiProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(authProvider).token),
);
final ordersProvider = FutureProvider.autoDispose.family<List<dynamic>, String>(
  (ref, restaurantId) async {
    return ref.watch(apiProvider).getList('/orders?restaurantId=$restaurantId');
  },
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        initialSessionProvider.overrideWithValue(
          AuthState(
            token: prefs.getString('accessToken'),
            restaurantId: prefs.getString('restaurantId'),
          ),
        ),
      ],
      child: const KitchenApp(),
    ),
  );
}

class KitchenApp extends ConsumerWidget {
  const KitchenApp({super.key});

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
          builder: (context, state) => const KitchenDashboardScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'RestoConnect Kitchen',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFDC2626)),
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
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
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
  const AuthState({this.token, this.restaurantId, this.loading = false});
  final String? token;
  final String? restaurantId;
  final bool loading;
  bool get isAuthenticated =>
      token != null && token!.isNotEmpty && restaurantId != null;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(super.initialState);

  Future<String?> sendOtp(String phone) async {
    state = AuthState(
      token: state.token,
      restaurantId: state.restaurantId,
      loading: true,
    );
    try {
      final response = await ApiClient(
        null,
      ).post('/auth/send-otp', {'phone': phone, 'role': 'KITCHEN'});
      return response['devOtp']?.toString();
    } finally {
      state = AuthState(token: state.token, restaurantId: state.restaurantId);
    }
  }

  Future<void> verifyOtp(String phone, String otp) async {
    state = AuthState(
      token: state.token,
      restaurantId: state.restaurantId,
      loading: true,
    );
    try {
      final response = await ApiClient(null).post('/auth/verify-otp', {
        'phone': phone,
        'otp': otp,
        'role': 'KITCHEN',
      });
      final token = response['accessToken'].toString();
      final user = response['user'] as Map<String, dynamic>;
      final restaurantId = user['restaurantId']?.toString();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('accessToken', token);
      if (restaurantId != null) {
        await prefs.setString('restaurantId', restaurantId);
      }
      state = AuthState(token: token, restaurantId: restaurantId);
    } finally {
      if (state.loading) {
        state = AuthState(token: state.token, restaurantId: state.restaurantId);
      }
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    await prefs.remove('restaurantId');
    state = const AuthState();
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final phoneController = TextEditingController();
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
                    'Kitchen Login',
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
                  if (devOtp != null) Text('Development OTP: $devOtp'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: auth.loading ? null : _verifyOtp,
                    child: auth.loading
                        ? const LinearProgressIndicator()
                        : const Text('Verify'),
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

class KitchenDashboardScreen extends ConsumerWidget {
  const KitchenDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.isAuthenticated) return const LoginScreen();
    return KitchenLiveBoard(restaurantId: auth.restaurantId!);
  }
}

class KitchenLiveBoard extends ConsumerStatefulWidget {
  const KitchenLiveBoard({required this.restaurantId, super.key});
  final String restaurantId;

  @override
  ConsumerState<KitchenLiveBoard> createState() => _KitchenLiveBoardState();
}

class _KitchenLiveBoardState extends ConsumerState<KitchenLiveBoard> {
  io.Socket? socket;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    socket?.dispose();
    super.dispose();
  }

  void _connect() {
    socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': ref.read(authProvider).token})
          .disableAutoConnect()
          .build(),
    );
    socket!
      ..on(
        'order_created',
        (_) => ref.invalidate(ordersProvider(widget.restaurantId)),
      )
      ..on(
        'order_updated',
        (_) => ref.invalidate(ordersProvider(widget.restaurantId)),
      )
      ..connect();
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersProvider(widget.restaurantId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen Board'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () =>
                ref.invalidate(ordersProvider(widget.restaurantId)),
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
      body: orders.when(
        data: (rows) {
          final active = rows
              .cast<Map<String, dynamic>>()
              .where(
                (order) =>
                    order['status'] != 'SERVED' &&
                    order['status'] != 'CANCELLED',
              )
              .toList();
          if (active.isEmpty) {
            return const Center(child: Text('No active orders'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 430,
              mainAxisExtent: 330,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: active.length,
            itemBuilder: (context, index) => KitchenOrderCard(
              order: active[index],
              restaurantId: widget.restaurantId,
            ),
          );
        },
        error: (error, stack) =>
            Center(child: ErrorPanel(message: error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class KitchenOrderCard extends ConsumerWidget {
  const KitchenOrderCard({
    required this.order,
    required this.restaurantId,
    super.key,
  });
  final Map<String, dynamic> order;
  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = (order['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final createdAt = DateTime.tryParse(order['createdAt']?.toString() ?? '');
    return Card(
      elevation: 0,
      color: statusColor(context, order['status'].toString()),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Table ${order['table']?['tableNumber'] ?? '-'}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Chip(label: Text(order['status'].toString())),
              ],
            ),
            if (createdAt != null)
              Text(DateFormat('hh:mm a').format(createdAt.toLocal())),
            const Divider(height: 24),
            Expanded(
              child: ListView(
                children: items.map((line) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${line['quantity']} x ${line['item']?['name'] ?? 'Item'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  );
                }).toList(),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                KitchenAction(
                  orderId: order['id'].toString(),
                  restaurantId: restaurantId,
                  status: 'PREPARING',
                  label: 'Accept',
                ),
                KitchenAction(
                  orderId: order['id'].toString(),
                  restaurantId: restaurantId,
                  status: 'PREPARING',
                  label: 'Preparing',
                ),
                KitchenAction(
                  orderId: order['id'].toString(),
                  restaurantId: restaurantId,
                  status: 'READY',
                  label: 'Ready',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class KitchenAction extends ConsumerWidget {
  const KitchenAction({
    required this.orderId,
    required this.restaurantId,
    required this.status,
    required this.label,
    super.key,
  });

  final String orderId;
  final String restaurantId;
  final String status;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton(
      onPressed: () async {
        await ref.read(apiProvider).patch('/orders/$orderId/status', {
          'status': status,
        });
        ref.invalidate(ordersProvider(restaurantId));
      },
      child: Text(label),
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

Color statusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    'PENDING' => scheme.surfaceContainerHighest,
    'PREPARING' => scheme.tertiaryContainer,
    'READY' => scheme.primaryContainer,
    _ => scheme.surface,
  };
}
