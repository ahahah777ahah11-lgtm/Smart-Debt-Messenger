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
// التطبيق الرئيسي
// ==========================================

class SmartDebtApp extends StatelessWidget {
  const SmartDebtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'المديونية الذكية',
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
// قاعدة البيانات المحلية
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
        throw Exception('العميل غير موجود');
      }

      final oldBalance = (result.first['balance'] as num).toDouble();

      // الدين يزيد الرصيد المستحق.
      // السداد ينقص الرصيد المستحق.
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

        // تجنب تكرار العميل إذا كان الاسم ورقم الهاتف متطابقين.
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
// الشاشة الرئيسية
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
        title: const Text('المديونية الذكية'),
        actions: [
          IconButton(
            tooltip: 'استيراد CSV',
            onPressed: importCSV,
            icon: const Icon(Icons.file_upload_outlined),
          ),
          IconButton(
            tooltip: 'تحديث',
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
        label: const Text('إضافة عميل'),
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
                    'إدارة العملاء',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو رقم الهاتف',
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
                      filterButton('الكل', 0),
                      filterButton('عليهم ديون', 1),
                      filterButton('لهم أرصدة', 2),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (filteredCustomers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(
                        child: Text('لا توجد بيانات لعرضها'),
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
              'ملخص الحسابات',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            summaryRow(
              'عدد العملاء',
              '${customers.length}',
              Icons.people_alt_outlined,
            ),
            const Divider(color: Colors.white30, height: 25),
            summaryRow(
              'إجمالي المبالغ المستحقة لك',
              money(totalDebt),
              Icons.account_balance_wallet_outlined,
            ),
            const Divider(color: Colors.white30, height: 25),
            summaryRow(
              'إجمالي المبالغ المستحقة للعملاء',
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
        ? 'عليه'
        : balance < 0
            ? 'له'
            : 'الحساب متوازن';

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
                customer['phone'].toString().isEmpty ? 'لا يوجد رقم هاتف' : customer['phone'].toString(),
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
                    child: Text('سجل الحركات'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('حذف العميل'),
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
                  const Text('الرصيد: '),
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
                  label: const Text('إضافة دين'),
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
                  label: const Text('تسجيل سداد'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => sendSMS(customer),
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('رسالة SMS'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // إضافة عميل
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
          title: const Text('إضافة عميل جديد'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم العميل',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'أدخل اسم العميل';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                    ),
                  ),
                  TextFormField(
                    controller: balanceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'الرصيد الابتدائي',
                      helperText: 'موجب = عليه دين، سالب = له رصيد',
                    ),
                    validator: (value) {
                      if (double.tryParse(value ?? '') == null) {
                        return 'أدخل مبلغًا صحيحًا';
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
              child: const Text('إلغاء'),
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
              child: const Text('حفظ'),
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
  // تسجيل دين أو دفعة
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
          title: Text(isDebt ? 'إضافة دين' : 'تسجيل سداد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('العميل: ${customer['name']}'),
              TextField(
                controller: amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'المبلغ',
                ),
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'البيان أو الملاحظة',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim());

                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('أدخل مبلغًا أكبر من صفر'),
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
              child: const Text('حفظ الحركة'),
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
  // إرسال رسالة SMS
  // ========================================

  Future<void> sendSMS(Map<String, dynamic> customer) async {
    final phone = customer['phone'].toString().trim();

    if (phone.isEmpty) {
      showMessage('أضف رقم هاتف العميل أولًا');
      return;
    }

    final balance = (customer['balance'] as num).toDouble();

    if (balance <= 0) {
      showMessage('لا يوجد مبلغ مستحق على هذا العميل');
      return;
    }

    final name = customer['name'].toString();

    final message =
        'مرحبًا $name، نذكرك بأن الرصيد المستحق عليك هو ${money(balance)}. نرجو تسوية الحساب، وشكرًا لك.';

    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
    );

    try {
      final launched = await launchUrl(uri);
      if (launched == false) {
        showMessage('تعذر فتح تطبيق الرسائل على الهاتف');
      }
    } catch (e) {
      showMessage('تعذر فتح تطبيق الرسائل');
    }
  }

  // ========================================
  // سجل الحركات
  // ========================================

  Future<void> showHistory(int customerId, String name) async {
    final transactions = await DebtDatabase.instance.getTransactions(customerId);

    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('سجل حركات $name'),
          content: SizedBox(
            width: double.maxFinite,
            child: transactions.isEmpty
                ? const Text('لا توجد حركات مسجلة')
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
                        title: Text('${isDebt ? 'دين' : 'سداد'}: ${money(amount)}'),
                        subtitle: Text('${item['note']}\n${item['created_at']}'),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  // ========================================
  // حذف عميل
  // ========================================

  Future<void> confirmDelete(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text(
            'هل تريد حذف العميل $name وسجل حركاته؟ لا يمكن التراجع عن هذه العملية.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف'),
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
  // استيراد CSV
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
        showMessage('تعذر قراءة الملف');
        return;
      }

      final text = utf8.decode(bytes, allowMalformed: true);

      final rows = CsvToListConverter(shouldParseNumbers: false).convert(text);

      if (rows.isEmpty) {
        showMessage('الملف فارغ');
        return;
      }

      final firstRow = rows.first.map((value) => value.toString().trim().toLowerCase()).toList();

      // try to auto-detect header columns
      int nameIndex = firstRow.indexWhere((v) => ['name', 'name_ar', 'الاسم', 'اسم'].contains(v));
      int phoneIndex = firstRow.indexWhere((v) => ['phone', 'tel', 'telephone', 'رقم', 'phone_number', 'هاتف'].contains(v));
      int balanceIndex = firstRow.indexWhere((v) => ['balance', 'amount', 'الرصيد', 'value'].contains(v));

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
        showMessage('لم يتم العثور على بيانات صالحة في الملف');
        return;
      }

      await DebtDatabase.instance.importCustomers(parsed);
      await refreshCustomers();

      showMessage('تم استيراد ${parsed.length} عميل بنجاح');
    } catch (e) {
      showMessage('تعذر استيراد الملف: ${e.toString()}');
    }
  }

  // Helper for showing SnackBar messages
  void showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
