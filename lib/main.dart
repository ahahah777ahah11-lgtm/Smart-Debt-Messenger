// Full corrected lib/main.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DebtDatabase.instance.database;

  runApp(const SmartDebtApp());
}

// ==========================================
// ط§ظ„طھط·ط¨ظٹظ‚ ط§ظ„ط±ط¦ظٹط³ظٹ
// ==========================================

class SmartDebtApp extends StatelessWidget {
  const SmartDebtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ط§ظ„ظ…ط¯ظٹظˆظ†ظٹط© ط§ظ„ط°ظƒظٹط©',
      locale: const Locale('ar'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF087F8C),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Color(0xFF087F8C),
          foregroundColor: Colors.white,
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomePage(),
      ),
    );
  }
}

// ==========================================
// ظ‚ط§ط¹ط¯ط© ط§ظ„ط¨ظٹط§ظ†ط§طھ ط§ظ„ظ…ط­ظ„ظٹط©
// ==========================================

class DebtDatabase {
  DebtDatabase._();

  static final DebtDatabase instance = DebtDatabase._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'smart_debt.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL DEFAULT '',
            balance REAL NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE transactions_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER NOT NULL,
            amount REAL NOT NULL,
            type TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
          )
        ''');
      },
    );

    return _database!;
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    final db = await database;

    return db.query(
      'customers',
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<int> addCustomer({
    required String name,
    required String phone,
    required double balance,
  }) async {
    final db = await database;

    return db.insert('customers', {
      'name': name,
      'phone': phone,
      'balance': balance,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateBalance({
    required int customerId,
    required double amount,
    required String type,
    required String note,
  }) async {
    final db = await database;

    await db.transaction((txn) async {
      final result = await txn.query(
        'customers',
        columns: ['balance'],
        where: 'id = ?',
        whereArgs: [customerId],
      );

      if (result.isEmpty) {
        throw Exception('ط§ظ„ط¹ظ…ظٹظ„ ط؛ظٹط± ظ…ظˆط¬ظˆط¯');
      }

      final oldBalance = (result.first['balance'] as num).toDouble();

      // ط§ظ„ط¯ظٹظ† ظٹط²ظٹط¯ ط§ظ„ط±طµظٹط¯ ط§ظ„ظ…ط³طھط­ظ‚.
      // ط§ظ„ط³ط¯ط§ط¯ ظٹظ†ظ‚طµ ط§ظ„ط±طµظٹط¯ ط§ظ„ظ…ط³طھط­ظ‚.
      final newBalance = type == 'debt' ? oldBalance + amount : oldBalance - amount;

      await txn.update(
        'customers',
        {'balance': newBalance},
        where: 'id = ?',
        whereArgs: [customerId],
      );

      await txn.insert('transactions_history', {
        'customer_id': customerId,
        'amount': amount,
        'type': type,
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> deleteCustomer(int id) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete(
        'transactions_history',
        where: 'customer_id = ?',
        whereArgs: [id],
      );

      await txn.delete(
        'customers',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getTransactions(
    int customerId,
  ) async {
    final db = await database;

    return db.query(
      'transactions_history',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'id DESC',
    );
  }

  Future<void> importCustomers(
    List<Map<String, dynamic>> customers,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      for (final customer in customers) {
        final name = (customer['name'] ?? '').toString().trim();

        if (name.isEmpty) continue;

        final phone = (customer['phone'] ?? '').toString().trim();

        final rawBalance = customer['balance'];
        final balance = rawBalance is num
            ? rawBalance.toDouble()
            : double.tryParse(
                  rawBalance.toString().replaceAll(',', ''),
                ) ??
                0.0;

        // طھط¬ظ†ط¨ طھظƒط±ط§ط± ط§ظ„ط¹ظ…ظٹظ„ ط¥ط°ط§ ظƒط§ظ† ط§ظ„ط§ط³ظ… ظˆط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ ظ…طھط·ط§ط¨ظ‚ظٹظ†.
        final existing = await txn.query(
          'customers',
          columns: ['id'],
          where: 'name = ? AND phone = ?',
          whereArgs: [name, phone],
          limit: 1,
        );

        if (existing.isNotEmpty) {
          await txn.update(
            'customers',
            {'balance': balance},
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        } else {
          await txn.insert('customers', {
            'name': name,
            'phone': phone,
            'balance': balance,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }
    });
  }

  Future<Map<String, double>> getSummary() async {
    final db = await database;

    final rows = await db.query('customers');

    double debt = 0;
    double credit = 0;

    for (final row in rows) {
      final balance = (row['balance'] as num).toDouble();

      if (balance > 0) {
        debt += balance;
      } else {
        credit += balance.abs();
      }
    }

    return {
      'count': rows.length.toDouble(),
      'debt': debt,
      'credit': credit,
    };
  }
}

// ==========================================
// ط§ظ„ط´ط§ط´ط© ط§ظ„ط±ط¦ظٹط³ظٹط©
// ==========================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> customers = [];

  bool loading = true;
  String searchText = '';
  int selectedTab = 0;

  @override
  void initState() {
    super.initState();
    refreshCustomers();
  }

  Future<void> refreshCustomers() async {
    setState(() => loading = true);

    final data = await DebtDatabase.instance.getCustomers();

    if (!mounted) return;

    setState(() {
      customers = data;
      loading = false;
    });
  }

  double get totalDebt {
    return customers.fold<double>(0, (sum, customer) {
      final balance = (customer['balance'] as num).toDouble();

      return sum + (balance > 0 ? balance : 0);
    });
  }

  double get totalCredit {
    return customers.fold<double>(0, (sum, customer) {
      final balance = (customer['balance'] as num).toDouble();

      return sum + (balance < 0 ? balance.abs() : 0);
    });
  }

  List<Map<String, dynamic>> get filteredCustomers {
    return customers.where((customer) {
      final name = customer['name'].toString().toLowerCase();
      final phone = customer['phone'].toString();

      final matchesSearch = name.contains(searchText.toLowerCase()) || phone.contains(searchText);

      if (!matchesSearch) return false;

      if (selectedTab == 1) {
        return (customer['balance'] as num) > 0;
      }

      if (selectedTab == 2) {
        return (customer['balance'] as num) < 0;
      }

      return true;
    }).toList();
  }

  String money(num value) => value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ط§ظ„ظ…ط¯ظٹظˆظ†ظٹط© ط§ظ„ط°ظƒظٹط©'),
        actions: [
          IconButton(
            tooltip: 'ط§ط³طھظٹط±ط§ط¯ CSV',
            onPressed: importCSV,
            icon: const Icon(Icons.file_upload_outlined),
          ),
          IconButton(
            tooltip: 'طھط­ط¯ظٹط«',
            onPressed: refreshCustomers,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await showCustomerForm(context);
          await refreshCustomers();
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('ط¥ط¶ط§ظپط© ط¹ظ…ظٹظ„'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: refreshCustomers,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  summaryCard(),
                  const SizedBox(height: 18),
                  const Text(
                    'ط¥ط¯ط§ط±ط© ط§ظ„ط¹ظ…ظ„ط§ط،',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'ط§ط¨ط­ط« ط¨ط§ظ„ط§ط³ظ… ط£ظˆ ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => searchText = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      filterButton('ط§ظ„ظƒظ„', 0),
                      filterButton('ط¹ظ„ظٹظ‡ظ… ط¯ظٹظˆظ†', 1),
                      filterButton('ظ„ظ‡ظ… ط£ط±طµط¯ط©', 2),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (filteredCustomers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(
                        child: Text('ظ„ط§ طھظˆط¬ط¯ ط¨ظٹط§ظ†ط§طھ ظ„ط¹ط±ط¶ظ‡ط§'),
                      ),
                    ),
                  ...filteredCustomers.map(customerCard),
                  const SizedBox(height: 90),
                ],
              ),
            ),
    );
  }

  Widget summaryCard() {
    return Card(
      elevation: 0,
      color: const Color(0xFF087F8C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ظ…ظ„ط®طµ ط§ظ„ط­ط³ط§ط¨ط§طھ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            summaryRow(
              'ط¹ط¯ط¯ ط§ظ„ط¹ظ…ظ„ط§ط،',
              '${customers.length}',
              Icons.people_alt_outlined,
            ),
            const Divider(color: Colors.white30, height: 25),
            summaryRow(
              'ط¥ط¬ظ…ط§ظ„ظٹ ط§ظ„ظ…ط¨ط§ظ„ط؛ ط§ظ„ظ…ط³طھط­ظ‚ط© ظ„ظƒ',
              money(totalDebt),
              Icons.account_balance_wallet_outlined,
            ),
            const Divider(color: Colors.white30, height: 25),
            summaryRow(
              'ط¥ط¬ظ…ط§ظ„ظٹ ط§ظ„ظ…ط¨ط§ظ„ط؛ ط§ظ„ظ…ط³طھط­ظ‚ط© ظ„ظ„ط¹ظ…ظ„ط§ط،',
              money(totalCredit),
              Icons.payments_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget summaryRow(String title, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget filterButton(String title, int index) {
    return ChoiceChip(
      label: Text(title),
      selected: selectedTab == index,
      onSelected: (_) {
        setState(() => selectedTab = index);
      },
    );
  }

  Widget customerCard(Map<String, dynamic> customer) {
    final balance = (customer['balance'] as num).toDouble();
    final id = customer['id'] as int;

    final Color balanceColor = balance > 0
        ? Colors.red.shade700
        : balance < 0
            ? Colors.green.shade700
            : Colors.blueGrey;

    final String balanceLabel = balance > 0
        ? 'ط¹ظ„ظٹظ‡'
        : balance < 0
            ? 'ظ„ظ‡'
            : 'ط§ظ„ط­ط³ط§ط¨ ظ…طھظˆط§ط²ظ†';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE0F2F1),
                child: Text(
                  customer['name'].toString().isNotEmpty ? customer['name'].toString()[0] : '?',
                  style: const TextStyle(
                    color: Color(0xFF087F8C),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                customer['name'].toString(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                customer['phone'].toString().isEmpty ? 'ظ„ط§ ظٹظˆط¬ط¯ ط±ظ‚ظ… ظ‡ط§طھظپ' : customer['phone'].toString(),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'history') {
                    await showHistory(id, customer['name'].toString());
                  }

                  if (action == 'delete') {
                    await confirmDelete(id, customer['name'].toString());
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'history',
                    child: Text('ط³ط¬ظ„ ط§ظ„ط­ط±ظƒط§طھ'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('ط­ط°ظپ ط§ظ„ط¹ظ…ظٹظ„'),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: balanceColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Text('ط§ظ„ط±طµظٹط¯: '),
                  Text(
                    '$balanceLabel ${money(balance.abs())}',
                    style: TextStyle(
                      color: balanceColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await showTransactionForm(
                      customer,
                      'debt',
                    );
                    await refreshCustomers();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('ط¥ط¶ط§ظپط© ط¯ظٹظ†'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await showTransactionForm(
                      customer,
                      'payment',
                    );
                    await refreshCustomers();
                  },
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('طھط³ط¬ظٹظ„ ط³ط¯ط§ط¯'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => sendSMS(customer),
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('ط±ط³ط§ظ„ط© SMS'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // ط¥ط¶ط§ظپط© ط¹ظ…ظٹظ„
  // ========================================

  Future<void> showCustomerForm(BuildContext context) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final balanceController = TextEditingController(text: '0');

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('ط¥ط¶ط§ظپط© ط¹ظ…ظٹظ„ ط¬ط¯ظٹط¯'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'ط§ط³ظ… ط§ظ„ط¹ظ…ظٹظ„',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'ط£ط¯ط®ظ„ ط§ط³ظ… ط§ظ„ط¹ظ…ظٹظ„';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ',
                    ),
                  ),
                  TextFormField(
                    controller: balanceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'ط§ظ„ط±طµظٹط¯ ط§ظ„ط§ط¨طھط¯ط§ط¦ظٹ',
                      helperText: 'ظ…ظˆط¬ط¨ = ط¹ظ„ظٹظ‡ ط¯ظٹظ†طŒ ط³ط§ظ„ط¨ = ظ„ظ‡ ط±طµظٹط¯',
                    ),
                    validator: (value) {
                      if (double.tryParse(value ?? '') == null) {
                        return 'ط£ط¯ط®ظ„ ظ…ط¨ظ„ط؛ظ‹ط§ طµط­ظٹط­ظ‹ط§';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ط¥ظ„ط؛ط§ط،'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                final balance = double.parse(balanceController.text.trim());

                await DebtDatabase.instance.addCustomer(
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  balance: balance,
                );

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('ط­ظپط¸'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
    balanceController.dispose();

    if (result == true) {
      await refreshCustomers();
    }
  }

  // ========================================
  // طھط³ط¬ظٹظ„ ط¯ظٹظ† ط£ظˆ ط¯ظپط¹ط©
  // ========================================

  Future<void> showTransactionForm(
    Map<String, dynamic> customer,
    String type,
  ) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    final isDebt = type == 'debt';

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isDebt ? 'ط¥ط¶ط§ظپط© ط¯ظٹظ†' : 'طھط³ط¬ظٹظ„ ط³ط¯ط§ط¯'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ط§ظ„ط¹ظ…ظٹظ„: ${customer['name']}'),
              TextField(
                controller: amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'ط§ظ„ظ…ط¨ظ„ط؛',
                ),
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'ط§ظ„ط¨ظٹط§ظ† ط£ظˆ ط§ظ„ظ…ظ„ط§ط­ط¸ط©',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ط¥ظ„ط؛ط§ط،'),
            ),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim());

                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ط£ط¯ط®ظ„ ظ…ط¨ظ„ط؛ظ‹ط§ ط£ظƒط¨ط± ظ…ظ† طµظپط±'),
                    ),
                  );
                  return;
                }

                await DebtDatabase.instance.updateBalance(
                  customerId: customer['id'] as int,
                  amount: amount,
                  type: type,
                  note: noteController.text.trim(),
                );

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('ط­ظپط¸ ط§ظ„ط­ط±ظƒط©'),
            ),
          ],
        );
      },
    );

    amountController.dispose();
    noteController.dispose();

    if (result == true) {
      await refreshCustomers();
    }
  }

  // ========================================
  // ط¥ط±ط³ط§ظ„ ط±ط³ط§ظ„ط© SMS
  // ========================================

  Future<void> sendSMS(Map<String, dynamic> customer) async {
    final phone = customer['phone'].toString().trim();

    if (phone.isEmpty) {
      showMessage('ط£ط¶ظپ ط±ظ‚ظ… ظ‡ط§طھظپ ط§ظ„ط¹ظ…ظٹظ„ ط£ظˆظ„ظ‹ط§');
      return;
    }

    final balance = (customer['balance'] as num).toDouble();

    if (balance <= 0) {
      showMessage('ظ„ط§ ظٹظˆط¬ط¯ ظ…ط¨ظ„ط؛ ظ…ط³طھط­ظ‚ ط¹ظ„ظ‰ ظ‡ط°ط§ ط§ظ„ط¹ظ…ظٹظ„');
      return;
    }

    final name = customer['name'].toString();

    final message =
        'ظ…ط±ط­ط¨ظ‹ط§ $nameطŒ ظ†ط°ظƒط±ظƒ ط¨ط£ظ† ط§ظ„ط±طµظٹط¯ ط§ظ„ظ…ط³طھط­ظ‚ ط¹ظ„ظٹظƒ ظ‡ظˆ ${money(balance)}. ظ†ط±ط¬ظˆ طھط³ظˆظٹط© ط§ظ„ط­ط³ط§ط¨طŒ ظˆط´ظƒط±ظ‹ط§ ظ„ظƒ.';

    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
    );

    try {
      final launched = await launchUrl(uri);
      if (launched == false) {
        showMessage('طھط¹ط°ط± ظپطھط­ طھط·ط¨ظٹظ‚ ط§ظ„ط±ط³ط§ط¦ظ„ ط¹ظ„ظ‰ ط§ظ„ظ‡ط§طھظپ');
      }
    } catch (e) {
      showMessage('طھط¹ط°ط± ظپطھط­ طھط·ط¨ظٹظ‚ ط§ظ„ط±ط³ط§ط¦ظ„');
    }
  }

  // ========================================
  // ط³ط¬ظ„ ط§ظ„ط­ط±ظƒط§طھ
  // ========================================

  Future<void> showHistory(int customerId, String name) async {
    final transactions = await DebtDatabase.instance.getTransactions(customerId);

    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('ط³ط¬ظ„ ط­ط±ظƒط§طھ $name'),
          content: SizedBox(
            width: double.maxFinite,
            child: transactions.isEmpty
                ? const Text('ظ„ط§ طھظˆط¬ط¯ ط­ط±ظƒط§طھ ظ…ط³ط¬ظ„ط©')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: transactions.length,
                    itemBuilder: (_, index) {
                      final item = transactions[index];

                      final isDebt = item['type'] == 'debt';

                      final amount = (item['amount'] as num).toDouble();

                      return ListTile(
                        leading: Icon(
                          isDebt ? Icons.add_circle_outline : Icons.remove_circle_outline,
                          color: isDebt ? Colors.red : Colors.green,
                        ),
                        title: Text('${isDebt ? 'ط¯ظٹظ†' : 'ط³ط¯ط§ط¯'}: ${money(amount)}'),
                        subtitle: Text('${item['note']}\n${item['created_at']}'),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ط¥ط؛ظ„ط§ظ‚'),
            ),
          ],
        );
      },
    );
  }

  // ========================================
  // ط­ط°ظپ ط¹ظ…ظٹظ„
  // ========================================

  Future<void> confirmDelete(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('طھط£ظƒظٹط¯ ط§ظ„ط­ط°ظپ'),
          content: Text(
            'ظ‡ظ„ طھط±ظٹط¯ ط­ط°ظپ ط§ظ„ط¹ظ…ظٹظ„ $name ظˆط³ط¬ظ„ ط­ط±ظƒط§طھظ‡طں ظ„ط§ ظٹظ…ظƒظ† ط§ظ„طھط±ط§ط¬ط¹ ط¹ظ† ظ‡ط°ظ‡ ط§ظ„ط¹ظ…ظ„ظٹط©.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ط¥ظ„ط؛ط§ط،'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('ط­ط°ظپ'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await DebtDatabase.instance.deleteCustomer(id);
      await refreshCustomers();
    }
  }

  // ========================================
  // ط§ط³طھظٹط±ط§ط¯ CSV
  // ========================================

  Future<void> importCSV() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final Uint8List? bytes = file.bytes;

      if (bytes == null) {
        showMessage('طھط¹ط°ط± ظ‚ط±ط§ط،ط© ط§ظ„ظ…ظ„ظپ');
        return;
      }

      final text = utf8.decode(bytes, allowMalformed: true);

      final rows = CsvToListConverter(shouldParseNumbers: false).convert(text);

      if (rows.isEmpty) {
        showMessage('ط§ظ„ظ…ظ„ظپ ظپط§ط±ط؛');
        return;
      }

      final firstRow = rows.first.map((value) => value.toString().trim().toLowerCase()).toList();

      // try to auto-detect header columns
      int nameIndex = firstRow.indexWhere((v) => ['name', 'name_ar', 'ط§ظ„ط§ط³ظ…', 'ط§ط³ظ…'].contains(v));
      int phoneIndex = firstRow.indexWhere((v) => ['phone', 'tel', 'telephone', 'ط±ظ‚ظ…', 'phone_number', 'ظ‡ط§طھظپ'].contains(v));
      int balanceIndex = firstRow.indexWhere((v) => ['balance', 'amount', 'ط§ظ„ط±طµظٹط¯', 'value'].contains(v));

      // If headers not detected, assume first three columns in order name, phone, balance
      final startRow = (nameIndex >= 0 || phoneIndex >= 0 || balanceIndex >= 0) ? 1 : 0;
      if (startRow == 0) {
        // fallback to indexes
        nameIndex = 0;
        phoneIndex = 1;
        balanceIndex = 2;
      } else {
        nameIndex = nameIndex >= 0 ? nameIndex : 0;
        phoneIndex = phoneIndex >= 0 ? phoneIndex : 1;
        balanceIndex = balanceIndex >= 0 ? balanceIndex : 2;
      }

      final List<Map<String, dynamic>> parsed = [];
      for (final row in rows.skip(startRow)) {
        if (row is! List) continue;
        final values = row.map((v) => v.toString().trim()).toList();
        final name = nameIndex < values.length ? values[nameIndex] : '';
        if (name.isEmpty) continue;
        final phone = phoneIndex < values.length ? values[phoneIndex] : '';
        final balanceStr = balanceIndex < values.length ? values[balanceIndex] : '0';
        final balance = double.tryParse(balanceStr.replaceAll(',', '')) ?? 0.0;

        parsed.add({
          'name': name,
          'phone': phone,
          'balance': balance,
        });
      }

      if (parsed.isEmpty) {
        showMessage('ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط¨ظٹط§ظ†ط§طھ طµط§ظ„ط­ط© ظپظٹ ط§ظ„ظ…ظ„ظپ');
        return;
      }

      await DebtDatabase.instance.importCustomers(parsed);
      await refreshCustomers();

      showMessage('طھظ… ط§ط³طھظٹط±ط§ط¯ ${parsed.length} ط¹ظ…ظٹظ„ ط¨ظ†ط¬ط§ط­');
    } catch (e) {
      showMessage('طھط¹ط°ط± ط§ط³طھظٹط±ط§ط¯ ط§ظ„ظ…ظ„ظپ: ${e.toString()}');
    }
  }

  // Helper for showing SnackBar messages
  void showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
