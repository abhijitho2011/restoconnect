import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api',
);
const socketUrl = String.fromEnvironment(
  'SOCKET_URL',
  defaultValue: 'http://localhost:3000',
);

final apiProvider = Provider<ApiClient>((ref) => ApiClient());
final menuProvider = FutureProvider.autoDispose.family<List<dynamic>, String>((
  ref,
  restaurantId,
) async {
  return ref.watch(apiProvider).getList('/menu/public/$restaurantId');
});
final tableOrdersProvider = FutureProvider.autoDispose
    .family<List<dynamic>, TableSession>((ref, session) async {
      return ref
          .watch(apiProvider)
          .getList('/orders/table/${session.restaurantId}/${session.tableId}');
    });
final cartProvider = StateNotifierProvider<CartController, List<CartLine>>(
  (ref) => CartController(),
);

void main() {
  runApp(const ProviderScope(child: CustomerApp()));
}

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const EmptyQrScreen()),
        GoRoute(
          path: '/r/:restaurantId/t/:tableId',
          builder: (context, state) => CustomerMenuScreen(
            restaurantId: state.pathParameters['restaurantId']!,
            tableId: state.pathParameters['tableId']!,
          ),
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'RestoConnect',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFEA580C)),
      ),
      routerConfig: router,
    );
  }
}

class EmptyQrScreen extends StatelessWidget {
  const EmptyQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                children: [
                  const Icon(Icons.qr_code_scanner, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Scan a table QR code',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ApiClient {
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decodeMap(response);
  }

  Future<List<dynamic>> getList(String path) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl$path'),
      headers: {'Content-Type': 'application/json'},
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

class TableSession {
  const TableSession(this.restaurantId, this.tableId);
  final String restaurantId;
  final String tableId;

  @override
  bool operator ==(Object other) {
    return other is TableSession &&
        other.restaurantId == restaurantId &&
        other.tableId == tableId;
  }

  @override
  int get hashCode => Object.hash(restaurantId, tableId);
}

class CartLine {
  const CartLine({
    required this.itemId,
    required this.name,
    required this.price,
    required this.quantity,
  });
  final String itemId;
  final String name;
  final double price;
  final int quantity;
  double get lineTotal => price * quantity;
}

class CartController extends StateNotifier<List<CartLine>> {
  CartController() : super(const []);

  void add(Map<String, dynamic> item) {
    final itemId = item['id'].toString();
    final existing = state.where((line) => line.itemId == itemId).firstOrNull;
    if (existing == null) {
      state = [
        ...state,
        CartLine(
          itemId: itemId,
          name: item['name'].toString(),
          price: toDouble(item['price']),
          quantity: 1,
        ),
      ];
      return;
    }

    state = [
      for (final line in state)
        if (line.itemId == itemId)
          CartLine(
            itemId: line.itemId,
            name: line.name,
            price: line.price,
            quantity: line.quantity + 1,
          )
        else
          line,
    ];
  }

  void remove(String itemId) {
    state = [
      for (final line in state)
        if (line.itemId == itemId && line.quantity > 1)
          CartLine(
            itemId: line.itemId,
            name: line.name,
            price: line.price,
            quantity: line.quantity - 1,
          )
        else if (line.itemId != itemId)
          line,
    ];
  }

  void clear() {
    state = const [];
  }
}

class CustomerMenuScreen extends ConsumerStatefulWidget {
  const CustomerMenuScreen({
    required this.restaurantId,
    required this.tableId,
    super.key,
  });

  final String restaurantId;
  final String tableId;

  @override
  ConsumerState<CustomerMenuScreen> createState() => _CustomerMenuScreenState();
}

class _CustomerMenuScreenState extends ConsumerState<CustomerMenuScreen> {
  io.Socket? socket;

  TableSession get session => TableSession(widget.restaurantId, widget.tableId);

  @override
  void initState() {
    super.initState();
    socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({
            'restaurantId': widget.restaurantId,
            'tableId': widget.tableId,
          })
          .disableAutoConnect()
          .build(),
    );
    socket!
      ..on('order_created', (_) => ref.invalidate(tableOrdersProvider(session)))
      ..on('order_updated', (_) => ref.invalidate(tableOrdersProvider(session)))
      ..connect();
  }

  @override
  void dispose() {
    socket?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(menuProvider(widget.restaurantId));
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(menuProvider(widget.restaurantId));
              ref.invalidate(tableOrdersProvider(session));
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final menuList = menu.when(
            data: (categories) =>
                MenuList(categories: categories.cast<Map<String, dynamic>>()),
            error: (error, stack) =>
                Center(child: ErrorPanel(message: error.toString())),
            loading: () => const Center(child: CircularProgressIndicator()),
          );
          final side = OrderSidePanel(session: session);
          if (wide) {
            return Row(
              children: [
                Expanded(child: menuList),
                SizedBox(width: 360, child: side),
              ],
            );
          }
          return Stack(
            children: [
              menuList,
              if (cart.isNotEmpty)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton.icon(
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => SizedBox(height: 520, child: side),
                        ),
                        icon: const Icon(Icons.shopping_cart),
                        label: Text(
                          '${cart.length} items • ${currency(cartTotal(cart))}',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class MenuList extends StatelessWidget {
  const MenuList({required this.categories, super.key});

  final List<Map<String, dynamic>> categories;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final items = (category['items'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                category['name'].toString(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ...items.map((item) => MenuItemCard(item: item)),
          ],
        );
      },
    );
  }
}

class MenuItemCard extends ConsumerWidget {
  const MenuItemCard({required this.item, super.key});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAr = item['modelGlbUrl'] != null || item['modelUsdzUrl'] != null;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 96,
                height: 96,
                child: item['imageUrl'] == null
                    ? ColoredBox(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.restaurant_menu),
                      )
                    : Image.network(
                        item['imageUrl'].toString(),
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'].toString(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(currency(item['price'])),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            ref.read(cartProvider.notifier).add(item),
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('Add'),
                      ),
                      if (hasAr)
                        OutlinedButton.icon(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => ArDialog(
                              name: item['name'].toString(),
                              glbUrl: item['modelGlbUrl']?.toString(),
                              usdzUrl: item['modelUsdzUrl']?.toString(),
                            ),
                          ),
                          icon: const Icon(Icons.view_in_ar),
                          label: const Text('View in AR'),
                        ),
                    ],
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

class OrderSidePanel extends ConsumerWidget {
  const OrderSidePanel({required this.session, super.key});
  final TableSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final orders = ref.watch(tableOrdersProvider(session));
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Cart', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (cart.isEmpty) const Text('No items added yet'),
          ...cart.map((line) => CartLineTile(line: line)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: cart.isEmpty
                ? null
                : () => _placeOrder(context, ref, cart),
            icon: const Icon(Icons.send),
            label: Text('Place order • ${currency(cartTotal(cart))}'),
          ),
          const Divider(height: 32),
          Text('Order Status', style: Theme.of(context).textTheme.titleLarge),
          orders.when(
            data: (rows) => Column(
              children: rows
                  .cast<Map<String, dynamic>>()
                  .map((order) => CustomerOrderTile(order: order))
                  .toList(),
            ),
            error: (error, stack) => ErrorPanel(message: error.toString()),
            loading: () => const LinearProgressIndicator(),
          ),
        ],
      ),
    );
  }

  Future<void> _placeOrder(
    BuildContext context,
    WidgetRef ref,
    List<CartLine> cart,
  ) async {
    try {
      await ref.read(apiProvider).post('/orders', {
        'restaurantId': session.restaurantId,
        'tableId': session.tableId,
        'items': cart
            .map((line) => {'itemId': line.itemId, 'quantity': line.quantity})
            .toList(),
      });
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(tableOrdersProvider(session));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Order placed')));
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class CartLineTile extends ConsumerWidget {
  const CartLineTile({required this.line, super.key});
  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(line.name),
      subtitle: Text('${line.quantity} x ${currency(line.price)}'),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Remove',
            onPressed: () =>
                ref.read(cartProvider.notifier).remove(line.itemId),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(currency(line.lineTotal)),
        ],
      ),
    );
  }
}

class CustomerOrderTile extends StatelessWidget {
  const CustomerOrderTile({required this.order, super.key});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final items = (order['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return Card(
      elevation: 0,
      child: ListTile(
        title: Text('${order['status']} • ${currency(order['totalAmount'])}'),
        subtitle: Text(
          items
              .map(
                (line) =>
                    '${line['quantity']} x ${line['item']?['name'] ?? 'Item'}',
              )
              .join(', '),
        ),
      ),
    );
  }
}

class ArDialog extends StatelessWidget {
  const ArDialog({
    required this.name,
    required this.glbUrl,
    required this.usdzUrl,
    super.key,
  });

  final String name;
  final String? glbUrl;
  final String? usdzUrl;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(name),
      content: SizedBox(
        width: 640,
        height: 480,
        child: glbUrl == null
            ? Center(
                child: Text(
                  usdzUrl == null
                      ? 'AR model is not available.'
                      : 'Open Quick Look on iPhone.',
                ),
              )
            : ArModelViewer(glbUrl: glbUrl!, usdzUrl: usdzUrl),
      ),
      actions: [
        if (usdzUrl != null)
          OutlinedButton.icon(
            onPressed: () =>
                launchUrl(Uri.parse(usdzUrl!), webOnlyWindowName: '_self'),
            icon: const Icon(Icons.phone_iphone),
            label: const Text('Quick Look'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class ArModelViewer extends StatefulWidget {
  const ArModelViewer({required this.glbUrl, required this.usdzUrl, super.key});
  final String glbUrl;
  final String? usdzUrl;

  @override
  State<ArModelViewer> createState() => _ArModelViewerState();
}

class _ArModelViewerState extends State<ArModelViewer> {
  late final String viewType;

  @override
  void initState() {
    super.initState();
    viewType = 'model-viewer-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final element = web.HTMLDivElement()
        ..style.width = '100%'
        ..style.height = '100%';
      final iosSrc = widget.usdzUrl == null
          ? ''
          : 'ios-src="${htmlEscape.convert(widget.usdzUrl!)}"';
      final modelViewerHtml =
          '<model-viewer src="${htmlEscape.convert(widget.glbUrl)}" $iosSrc ar ar-modes="webxr scene-viewer quick-look" camera-controls auto-rotate shadow-intensity="1" style="width:100%;height:100%;background:#f7f7f7;border-radius:8px;"></model-viewer>';
      element.setHTMLUnsafe(modelViewerHtml.toJS);
      return element;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: viewType);
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

double toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double cartTotal(List<CartLine> cart) =>
    cart.fold(0, (total, line) => total + line.lineTotal);

String currency(dynamic value) {
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
  ).format(toDouble(value));
}
