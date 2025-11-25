import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  final String timeZoneName = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(timeZoneName));

  const AndroidInitializationSettings android =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await notifications.initialize(const InitializationSettings(android: android));

  runApp(const MedicineReminderApp());
}

class Medicine {
  String id;
  String name;
  int timesPerDay;
  int totalTablets;
  bool notificationOnly;
  bool alarmSound;
  bool isActive;

  Medicine({
    required this.id,
    required this.name,
    required this.timesPerDay,
    required this.totalTablets,
    this.notificationOnly = true,
    this.alarmSound = false,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'timesPerDay': timesPerDay,
        'totalTablets': totalTablets,
        'notificationOnly': notificationOnly,
        'alarmSound': alarmSound,
        'isActive': isActive,
      };

  factory Medicine.fromJson(Map<String, dynamic> json) => Medicine(
        id: json['id'],
        name: json['name'],
        timesPerDay: json['timesPerDay'],
        totalTablets: json['totalTablets'],
        notificationOnly: json['notificationOnly'] ?? true,
        alarmSound: json['alarmSound'] ?? false,
        isActive: json['isActive'] ?? true,
      );
}

class MedicineReminderApp extends StatelessWidget {
  const MedicineReminderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const MedicineListScreen(),
    );
  }
}

class MedicineListScreen extends StatefulWidget {
  const MedicineListScreen({super.key});
  @override
  State<MedicineListScreen> createState() => _MedicineListScreenState();
}

class _MedicineListScreenState extends State<MedicineListScreen> {
  List<Medicine> medicines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('medicines');
    if (data != null) {
      setState(() {
        medicines = (jsonDecode(data) as List)
            .map((e) => Medicine.fromJson(e))
            .toList();
      });
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('medicines', jsonEncode(medicines.map((e) => e.toJson()).toList()));
  }

  void _add(Medicine m) {
    setState(() => medicines.add(m));
    _save();
    _schedule(m);
  }

  void _toggle(Medicine m) {
    setState(() => m.isActive = !m.isActive);
    _save();
    m.isActive ? _schedule(m) : _cancel(m);
  }

  Future<void> _schedule(Medicine m) async {
    await _cancel(m);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 8); // mulai jam 8 pagi
    final intervalMinutes = (1440 / m.timesPerDay).floor();

    for (int i = 0; i < m.timesPerDay; i++) {
      var time = today.add(Duration(minutes: i * intervalMinutes));
      if (time.isBefore(now)) time = time.add(const Duration(days: 1));

      final android = AndroidNotificationDetails(
        'med_channel',
        'Obat',
        importance: Importance.max,
        priority: Priority.high,
        playSound: m.alarmSound || !m.notificationOnly,
      );

      await notifications.zonedSchedule(
        int.parse(m.id + i.toString()),
        'Waktunya Minum Obat',
        '\( {m.name} • Dosis \){i + 1}',
        tz.TZDateTime.from(time, tz.local),
        NotificationDetails(android: android),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> _cancel(Medicine m) async {
    for (int i = 0; i < 10; i++) {
      await notifications.cancel(int.parse(m.id + i.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengingat Obat'), centerTitle: true),
      body: medicines.isEmpty
          ? const Center(child: Text('Belum ada obat', style: TextStyle(fontSize: 18, color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: medicines.length,
              itemBuilder: (_, i) {
                final m = medicines[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D1D1D),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    title: Text(
                      m.timesPerDay == 1 ? '1 kali sehari' : '$m kali sehari',
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w300),
                    ),
                    subtitle: Text('\( {m.name} • \){m.totalTablets} tablet'),
                    trailing: Switch(value: m.isActive, activeColor: Colors.blue, onChanged: (_) => _toggle(m)),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0A84FF),
        child: const Icon(Icons.add, size: 36),
        onPressed: () => Navigator.push(context, CupertinoPageRoute(builder: (_) => AddMedicineScreen(onSave: _add))),
      ),
    );
  }
}

// =================== HALAMAN TAMBAH OBAT (UI BARU CANTIK) ===================
class AddMedicineScreen extends StatefulWidget {
  final Function(Medicine) onSave;
  const AddMedicineScreen({super.key, required this.onSave});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _nameController = TextEditingController();
  int _timesPerDay = 1;
  int _totalTablets = 30;
  bool _notifOnly = true;
  bool _alarm = false;

  final List<Map<String, dynamic>> frequencies = [
    {'times': 1, 'interval': '24 jam'},
    {'times': 2, 'interval': '12 jam'},
    {'times': 3, 'interval': '8 jam'},
    {'times': 4, 'interval': '6 jam'},
    {'times': 5, 'interval': '≈4.8 jam'},
    {'times': 6, 'interval': '4 jam'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: TextButton(child: const Text('Batal', style: TextStyle(color: Colors.grey)), onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(
            onPressed: _nameController.text.trim().isEmpty
                ? null
                : () {
                    final med = Medicine(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: _nameController.text.trim(),
                      timesPerDay: _timesPerDay,
                      totalTablets: _totalTablets,
                      notificationOnly: _notifOnly,
                      alarmSound: _alarm,
                    );
                    widget.onSave(med);
                    Navigator.pop(context);
                  },
            child: const Text('Simpan', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        // Nama Obat - Kotak Putih
        const Text('Nama obat', style: TextStyle(fontSize: 17)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.black, fontSize: 18),
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Contoh: Paracetamol', hintStyle: TextStyle(color: Colors.grey)),
          ),
        ),

        const SizedBox(height: 32),

        // Jumlah Tablet - Kotak Putih
        const Text('Jumlah tablet / strip', style: TextStyle(fontSize: 17)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: TextField(
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.black, fontSize: 18),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: '$_totalTablets',
              hintStyle: const TextStyle(color: Colors.grey),
            ),
            onChanged: (v) => setState(() => _totalTablets = int.tryParse(v) ?? 30),
          ),
        ),

        const SizedBox(height: 40),

        // Frekuensi - Wheel Picker
        const Text('Berapa kali sehari?', style: TextStyle(fontSize: 17)),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: CupertinoPicker(
            itemExtent: 48,
            magnification: 1.2,
            useMagnifier: true,
            onSelectedItemChanged: (i) => setState(() => _timesPerDay = frequencies[i]['times']),
            children: frequencies.map((f) {
              return Center(
                child: Text(
                  '${f['times']} kali sehari',
                  style: const TextStyle(fontSize: 22),
                ),
              );
            }).toList(),
          ),
        ),
        Center(
          child: Text(
            'Setiap ${frequencies.firstWhere((e) => e['times'] == _timesPerDay)['interval']}',
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ),

        const SizedBox(height: 50),

        // Jenis Pengingat
        const Text('Jenis pengingat', style: TextStyle(fontSize: 17)),
        const SizedBox(height: 12),
        SwitchListTile(title: const Text('Notifikasi biasa'), value: _notifOnly, activeColor: Colors.blue, onChanged: (v) => setState(() => _notifOnly = v)),
        SwitchListTile(title: const Text('Alarm dengan suara'), value: _alarm, activeColor: Colors.blue, onChanged: (v) => setState(() => _alarm = v)),
      ]),
    );
  }
}