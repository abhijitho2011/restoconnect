import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
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

final initialTokenProvider = Provider<String?>((ref) => null);
final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(initialTokenProvider));
});
final apiProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(authProvider).token),
);

final restaurantsProvider = FutureProvider.autoDispose<List<dynamic>>((
  ref,
) async {
  return ref.watch(apiProvider).getList('/restaurants');
});
final currentRestaurantProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
      final restaurants = await ref.watch(restaurantsProvider.future);
      if (restaurants.isEmpty) return null;
      return restaurants.first as Map<String, dynamic>;
    });
final tablesProvider = FutureProvider.autoDispose.family<List<dynamic>, String>(
  (ref, restaurantId) async {
    return ref.watch(apiProvider).getList('/tables?restaurantId=$restaurantId');
  },
);
final categoriesProvider = FutureProvider.autoDispose
    .family<List<dynamic>, String>((ref, restaurantId) async {
      return ref
          .watch(apiProvider)
          .getList('/menu/categories?restaurantId=$restaurantId');
    });
final ordersProvider = FutureProvider.autoDispose.family<List<dynamic>, String>(
  (ref, restaurantId) async {
    return ref.watch(apiProvider).getList('/orders?restaurantId=$restaurantId');
  },
);
final kitchenUsersProvider = FutureProvider.autoDispose
    .family<List<dynamic>, String>((ref, restaurantId) async {
      return ref
          .watch(apiProvider)
          .getList('/users/kitchen?restaurantId=$restaurantId');
    });

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        initialTokenProvider.overrideWithValue(prefs.getString('accessToken')),
      ],
      child: const RestaurantApp(),
    ),
  );
}

class RestaurantApp extends ConsumerWidget {
  const RestaurantApp({super.key});

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
          builder: (context, state) => const RestaurantDashboardScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'RestoConnect Restaurant',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
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
      final response = await ApiClient(
        null,
      ).post('/auth/send-otp', {'phone': phone, 'role': 'RESTAURANT_OWNER'});
      return response['devOtp']?.toString();
    } finally {
      state = AuthState(token: state.token);
    }
  }

  Future<void> verifyOtp(String phone, String otp) async {
    state = AuthState(token: state.token, loading: true);
    try {
      final response = await ApiClient(null).post('/auth/verify-otp', {
        'phone': phone,
        'otp': otp,
        'role': 'RESTAURANT_OWNER',
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
                    'Restaurant Owner',
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

class RestaurantDashboardScreen extends ConsumerWidget {
  const RestaurantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(authProvider).isAuthenticated) {
      return const LoginScreen();
    }

    final restaurant = ref.watch(currentRestaurantProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurant Console'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(currentRestaurantProvider);
              ref.invalidate(restaurantsProvider);
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
      body: restaurant.when(
        data: (data) {
          if (data == null) {
            return const Center(
              child: Text('No restaurant is assigned to this owner account.'),
            );
          }
          final restaurantId = data['id'].toString();
          return LiveRestaurantView(
            restaurant: data,
            restaurantId: restaurantId,
          );
        },
        error: (error, stack) =>
            Center(child: ErrorPanel(message: error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class LiveRestaurantView extends ConsumerStatefulWidget {
  const LiveRestaurantView({
    required this.restaurant,
    required this.restaurantId,
    super.key,
  });

  final Map<String, dynamic> restaurant;
  final String restaurantId;

  @override
  ConsumerState<LiveRestaurantView> createState() => _LiveRestaurantViewState();
}

class _LiveRestaurantViewState extends ConsumerState<LiveRestaurantView> {
  io.Socket? socket;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(covariant LiveRestaurantView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.restaurantId != widget.restaurantId) {
      socket?.dispose();
      _connect();
    }
  }

  @override
  void dispose() {
    socket?.dispose();
    super.dispose();
  }

  void _connect() {
    final token = ref.read(authProvider).token;
    socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        HeaderPanel(restaurant: widget.restaurant),
        const SizedBox(height: 24),
        TablesSection(restaurantId: widget.restaurantId),
        const SizedBox(height: 24),
        MenuSection(restaurantId: widget.restaurantId),
        const SizedBox(height: 24),
        OrdersSection(restaurantId: widget.restaurantId),
        const SizedBox(height: 24),
        KitchenUsersSection(restaurantId: widget.restaurantId),
      ],
    );
  }
}

class HeaderPanel extends StatelessWidget {
  const HeaderPanel({required this.restaurant, super.key});

  final Map<String, dynamic> restaurant;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.storefront, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant['name']?.toString() ?? 'Restaurant',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    '${restaurant['status']} • ${restaurant['subscriptionPlan'] ?? 'No plan'}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TablesSection extends ConsumerWidget {
  const TablesSection({required this.restaurantId, super.key});
  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(tablesProvider(restaurantId));
    return Section(
      title: 'Tables and QR Codes',
      trailing: FilledButton.icon(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => CreateTableDialog(restaurantId: restaurantId),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Table'),
      ),
      child: tables.when(
        data: (rows) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: rows.map((raw) {
            final table = raw as Map<String, dynamic>;
            return SizedBox(
              width: 220,
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Table ${table['tableNumber']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      QrImageView(
                        data: table['qrCodeUrl'].toString(),
                        size: 140,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        table['qrCodeUrl'].toString(),
                        textAlign: TextAlign.center,
                      ),
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

class MenuSection extends ConsumerWidget {
  const MenuSection({required this.restaurantId, super.key});
  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider(restaurantId));
    return Section(
      title: 'Menu',
      trailing: Wrap(
        spacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => CreateCategoryDialog(restaurantId: restaurantId),
            ),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Category'),
          ),
          FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => CreateItemDialog(restaurantId: restaurantId),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Item'),
          ),
        ],
      ),
      child: categories.when(
        data: (rows) => Column(
          children: rows.map((raw) {
            final category = raw as Map<String, dynamic>;
            final items = (category['items'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>();
            return Card(
              elevation: 0,
              child: ExpansionTile(
                initiallyExpanded: true,
                title: Text(category['name'].toString()),
                children: items
                    .map(
                      (item) =>
                          MenuItemTile(item: item, restaurantId: restaurantId),
                    )
                    .toList(),
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

class MenuItemTile extends ConsumerWidget {
  const MenuItemTile({
    required this.item,
    required this.restaurantId,
    super.key,
  });

  final Map<String, dynamic> item;
  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = item['isAvailable'] == true;
    return ListTile(
      leading: item['imageUrl'] == null
          ? const CircleAvatar(child: Icon(Icons.restaurant_menu))
          : CircleAvatar(
              backgroundImage: NetworkImage(item['imageUrl'].toString()),
            ),
      title: Text(item['name'].toString()),
      subtitle: Text(
        '${currency(item['price'])}${item['modelGlbUrl'] == null ? '' : ' • AR ready'}',
      ),
      trailing: Switch(
        value: available,
        onChanged: (value) async {
          await ref.read(apiProvider).patch('/menu/items/${item['id']}', {
            'isAvailable': value,
          });
          ref.invalidate(categoriesProvider(restaurantId));
        },
      ),
    );
  }
}

class OrdersSection extends ConsumerWidget {
  const OrdersSection({required this.restaurantId, super.key});
  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider(restaurantId));
    return Section(
      title: 'Live Orders',
      child: orders.when(
        data: (rows) => Column(
          children: rows
              .map(
                (raw) => OrderTile(
                  order: raw as Map<String, dynamic>,
                  restaurantId: restaurantId,
                ),
              )
              .toList(),
        ),
        error: (error, stack) => ErrorPanel(message: error.toString()),
        loading: () => const LinearProgressIndicator(),
      ),
    );
  }
}

class OrderTile extends ConsumerWidget {
  const OrderTile({required this.order, required this.restaurantId, super.key});
  final Map<String, dynamic> order;
  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = (order['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Table ${order['table']?['tableNumber'] ?? '-'} • ${order['status']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(currency(order['totalAmount'])),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              items
                  .map(
                    (line) =>
                        '${line['quantity']} x ${line['item']?['name'] ?? 'Item'}',
                  )
                  .join(', '),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                StatusButton(
                  orderId: order['id'].toString(),
                  restaurantId: restaurantId,
                  label: 'Preparing',
                  status: 'PREPARING',
                ),
                StatusButton(
                  orderId: order['id'].toString(),
                  restaurantId: restaurantId,
                  label: 'Ready',
                  status: 'READY',
                ),
                StatusButton(
                  orderId: order['id'].toString(),
                  restaurantId: restaurantId,
                  label: 'Served',
                  status: 'SERVED',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class StatusButton extends ConsumerWidget {
  const StatusButton({
    required this.orderId,
    required this.restaurantId,
    required this.label,
    required this.status,
    super.key,
  });

  final String orderId;
  final String restaurantId;
  final String label;
  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton(
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

class KitchenUsersSection extends ConsumerWidget {
  const KitchenUsersSection({required this.restaurantId, super.key});
  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(kitchenUsersProvider(restaurantId));
    return Section(
      title: 'Kitchen Users',
      trailing: FilledButton.icon(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => CreateKitchenUserDialog(restaurantId: restaurantId),
        ),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Kitchen user'),
      ),
      child: users.when(
        data: (rows) => Column(
          children: rows.map((raw) {
            final user = raw as Map<String, dynamic>;
            return Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(user['phone'].toString()),
                subtitle: const Text('Kitchen staff'),
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

class CreateTableDialog extends ConsumerStatefulWidget {
  const CreateTableDialog({required this.restaurantId, super.key});
  final String restaurantId;

  @override
  ConsumerState<CreateTableDialog> createState() => _CreateTableDialogState();
}

class _CreateTableDialogState extends ConsumerState<CreateTableDialog> {
  final tableNumber = TextEditingController();

  @override
  void dispose() {
    tableNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create table'),
      content: TextField(
        controller: tableNumber,
        decoration: const InputDecoration(labelText: 'Table number'),
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
    await ref.read(apiProvider).post('/tables', {
      'restaurantId': widget.restaurantId,
      'tableNumber': tableNumber.text.trim(),
    });
    ref.invalidate(tablesProvider(widget.restaurantId));
    if (mounted) Navigator.pop(context);
  }
}

class CreateCategoryDialog extends ConsumerStatefulWidget {
  const CreateCategoryDialog({required this.restaurantId, super.key});
  final String restaurantId;

  @override
  ConsumerState<CreateCategoryDialog> createState() =>
      _CreateCategoryDialogState();
}

class _CreateCategoryDialogState extends ConsumerState<CreateCategoryDialog> {
  final name = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create category'),
      content: TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Name'),
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
    await ref.read(apiProvider).post('/menu/categories', {
      'restaurantId': widget.restaurantId,
      'name': name.text.trim(),
    });
    ref.invalidate(categoriesProvider(widget.restaurantId));
    if (mounted) Navigator.pop(context);
  }
}

class CreateItemDialog extends ConsumerStatefulWidget {
  const CreateItemDialog({required this.restaurantId, super.key});
  final String restaurantId;

  @override
  ConsumerState<CreateItemDialog> createState() => _CreateItemDialogState();
}

class _CreateItemDialogState extends ConsumerState<CreateItemDialog> {
  final name = TextEditingController();
  final price = TextEditingController();
  final imageUrl = TextEditingController();
  final glbUrl = TextEditingController();
  final usdzUrl = TextEditingController();
  String? categoryId;

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    imageUrl.dispose();
    glbUrl.dispose();
    usdzUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider(widget.restaurantId));
    return AlertDialog(
      title: const Text('Create item'),
      content: SizedBox(
        width: 520,
        child: categories.when(
          data: (rows) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: rows.map((raw) {
                  final category = raw as Map<String, dynamic>;
                  return DropdownMenuItem(
                    value: category['id'].toString(),
                    child: Text(category['name'].toString()),
                  );
                }).toList(),
                onChanged: (value) => setState(() => categoryId = value),
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: price,
                decoration: const InputDecoration(labelText: 'Price'),
              ),
              TextField(
                controller: imageUrl,
                decoration: const InputDecoration(labelText: 'Image URL'),
              ),
              TextField(
                controller: glbUrl,
                decoration: const InputDecoration(labelText: 'GLB URL'),
              ),
              TextField(
                controller: usdzUrl,
                decoration: const InputDecoration(labelText: 'USDZ URL'),
              ),
            ],
          ),
          error: (error, stack) => ErrorPanel(message: error.toString()),
          loading: () => const LinearProgressIndicator(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: categoryId == null ? null : _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    await ref.read(apiProvider).post('/menu/items', {
      'categoryId': categoryId,
      'name': name.text.trim(),
      'price': double.parse(price.text.trim()),
      'imageUrl': imageUrl.text.trim().isEmpty ? null : imageUrl.text.trim(),
      'modelGlbUrl': glbUrl.text.trim().isEmpty ? null : glbUrl.text.trim(),
      'modelUsdzUrl': usdzUrl.text.trim().isEmpty ? null : usdzUrl.text.trim(),
      'isAvailable': true,
    });
    ref.invalidate(categoriesProvider(widget.restaurantId));
    if (mounted) Navigator.pop(context);
  }
}

class CreateKitchenUserDialog extends ConsumerStatefulWidget {
  const CreateKitchenUserDialog({required this.restaurantId, super.key});
  final String restaurantId;

  @override
  ConsumerState<CreateKitchenUserDialog> createState() =>
      _CreateKitchenUserDialogState();
}

class _CreateKitchenUserDialogState
    extends ConsumerState<CreateKitchenUserDialog> {
  final phone = TextEditingController();

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create kitchen user'),
      content: TextField(
        controller: phone,
        decoration: const InputDecoration(labelText: 'Mobile number'),
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
    await ref.read(apiProvider).post('/users/kitchen', {
      'restaurantId': widget.restaurantId,
      'phone': phone.text.trim(),
    });
    ref.invalidate(kitchenUsersProvider(widget.restaurantId));
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
