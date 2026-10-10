import 'package:flutter/material.dart';

void main() {
  runApp(const SmartDebtApp());
}

class SmartDebtApp extends StatelessWidget {
  const SmartDebtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'رسائل المديونية',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: const DebtHomePage(),
    );
  }
}

class Customer {
  String name;
  String phone;
  double balance;

  Customer({
    required this.name,
    required this.phone,
    required this.balance,
  });
}

class DebtHomePage extends StatefulWidget {
  const DebtHomePage({super.key});

  @override
  State<DebtHomePage> createState() => _DebtHomePageState();
}

class _DebtHomePageState extends State<DebtHomePage> {
  final List<Customer> customers = [
    Customer(
      name: 'أحمد محمد',
      phone: '770000001',
      balance: 15000,
    ),
    Customer(
      name: 'محمد علي',
      phone: '770000002',
      balance: 8000,
    ),
  ];

  final TextEditingController searchController =
      TextEditingController();

  String searchText = '';

  double get totalDebt => customers
      .where((c) => c.balance > 0)
      .fold(0.0, (sum, c) => sum + c.balance);

  void addCustomer() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final balanceController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة عميل'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم العميل',
                ),
              ),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                ),
              ),
              TextField(
                controller: balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'الرصيد المستحق',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              final balance =
                  double.tryParse(balanceController.text.trim());

              if (name.isEmpty ||
                  phone.isEmpty ||
                  balance == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('أدخل الاسم والهاتف ورصيداً صحيحاً'),
                  ),
                );
                return;
              }

              setState(() {
                customers.add(
                  Customer(
                    name: name,
                    phone: phone,
                    balance: balance,
                  ),
                );
              });

              Navigator.pop(dialogContext);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void updateBalance(Customer customer) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('تعديل رصيد ${customer.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: const InputDecoration(
            labelText: 'الرصيد الجديد',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final value =
                  double.tryParse(controller.text.trim());

              if (value == null) return;

              setState(() {
                customer.balance = value;
              });

              Navigator.pop(dialogContext);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCustomers = customers.where((customer) {
      return customer.name.contains(searchText) ||
          customer.phone.contains(searchText);
    }).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('رسائل المديونية'),
          actions: [
            IconButton(
              onPressed: addCustomer,
              icon: const Icon(Icons.person_add),
              tooltip: 'إضافة عميل',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: addCustomer,
          icon: const Icon(Icons.add),
          label: const Text('إضافة عميل'),
        ),
        body: Column(
          children: [
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إجمالي المديونية',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      totalDebt.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('عدد العملاء: ${customers.length}'),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: searchController,
                onChanged: (value) {
                  setState(() {
                    searchText = value.trim();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم أو رقم الهاتف',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: filteredCustomers.isEmpty
                  ? const Center(
                      child: Text('لا يوجد عملاء مطابقون للبحث'),
                    )
                  : ListView.builder(
                      itemCount: filteredCustomers.length,
                      itemBuilder: (context, index) {
                        final customer = filteredCustomers[index];

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(
                                customer.balance > 0
                                    ? Icons.person
                                    : Icons.check,
                              ),
                            ),
                            title: Text(customer.name),
                            subtitle: Text(
                              'الهاتف: ${customer.phone}\n'
                              'الرصيد: ${customer.balance.toStringAsFixed(2)}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: 'تعديل الرصيد',
                              onPressed: () =>
                                  updateBalance(customer),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}