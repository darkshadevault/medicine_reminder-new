import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  final String timeZoneName = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(timeZoneName));

  const AndroidInitializationSettings android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(android: android);
  await notifications.initialize(initSettings);

  runApp(const MedicineReminderApp());
}

class Medicine {
  String name;
  int timesPerDay;
  int totalTablets;
  bool notificationOnly;
  bool alarmSound;
  bool isActive;
  String id;

  Medicine({
    required this.name,
    required this.timesPerDay,
    required this.totalTablets,
    this.notificationOnly = true,
    this.alarmSound = false,
    this.isActive = true,
    required this.id,
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
        notificationOnly: json['notificationOnly'],
        alarmSound: json['alarmSound'],
        isActive: json['isActive'],
      );
}

class MedicineReminderApp extends StatelessWidget {
  const MedicineReminderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
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
    _loadMedicines();
  }

  Future<void> _loadMedicines() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('medicines');
    if (data != null) {
      final List<dynamic> jsonList = jsonDecode(data);
      setState(() {
        medicines = jsonList.map((e) => Medicine.fromJson(e)).toList();
      });
    }
  }

  Future<void> _saveMedicines() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(medicines.map((e) => e.toJson()).toList());
    prefs.setString('medicines', data);
  }

  void _addMedicine(Medicine med) {
    setState(() => medicines.add(med));
    _saveMedicines();
    _scheduleAllDoses(med);
  }

  void _toggleActive(Medicine med) {
    setState(() => med.isActive = !med.isActive);
    _saveMedicines();
    if (med.isActive) {
      _scheduleAllDoses(med);
    } else {
      _cancelAllDoses(med);
    }
  }

  Future<void> _scheduleAllDoses(Medicine med) async {
    await _cancelAllDoses(med); // bersihkan dulu

    // Contoh: dosis merata tiap hari mulai jam 8 pagi
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (int i = 0; i < med.timesPerDay; i++) {
      final minutesPerDose = 1440 ~/ med.timesPerDay; // 1440 menit dalam sehari
      final doseTime = today.add(Duration(minutes: 480 + i * minutesPerDose)); // mulai jam 8 pagi

      final scheduledDate = doseTime.isBefore(now) ? doseTime.add(const Duration(days: 1)) : doseTime;

      final androidDetails = AndroidNotificationDetails(
        'medicine_channel',
        'Pengingat Obat',
        channelDescription: 'Notifikasi minum obat',
        importance: Importance.max,
        priority: Priority.high,
        playSound: med.alarmSound || !med.notificationOnly,
        enableVibration: true,
      );

      await notifications.zonedSchedule(
        int.parse('${med.id}$i'),
        'Waktunya Minum Obat',
        '\( {med.name} – Dosis \){i + 1}/${med.timesPerDay}',
        tz.TZDateTime.from(scheduledDate, tz.local),
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> _cancelAllDoses(Medicine med) async {
    for (int i = 0; i < med.timesPerDay; i++) {
      await notifications.cancel(int.parse('${med.id}$i'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengingat Obat'),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: medicines.isEmpty
          ? const Center(child: Text('Belum ada obat', style: TextStyle(fontSize: 18, color: Colors.grey)))
          : ListView.builder(
              itemCount: medicines.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final med = medicines[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D1D1D),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    title: Text(
                      med.timesPerDay == 1 ? 'Sekali sehari' : '${med.timesPerDay} kali sehari',
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w300, height: 1),
                    ),
                    subtitle: Text(
                      '\( {med.name} • \){med.totalTablets} tablet tersisa',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    trailing: Switch(
                      value: med.isActive,
                      activeColor: Colors.blue,
                      onChanged: (_) => _toggleActive(med),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0A84FF),
        child: const Icon(Icons.add, size: 36),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddMedicineScreen(onSave: _addMedicine),
            fullscreenDialog: true,
          ),
        ),
      ),
    );
  }
}

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
  bool _notificationOnly = true;
  bool _alarmSound = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal', style: TextStyle(color: Colors.grey))),
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
                      notificationOnly: _notificationOnly,
                      alarmSound: _alarmSound,
                    );
                    widget.onSave(med);
                    Navigator.pop(context);
                  },
            child: const Text('Simpan', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        // Nama Obat
        TextField(
          controller: _nameController,
          style: const TextStyle(fontSize: 20),
          decoration: const InputDecoration(
            hintText: 'Nama obat (contoh: Paracetamol)',
            hintStyle: TextStyle(color: Colors.grey),
            border: InputBorder.none,
          ),
        ),
        const Divider(color: Colors.grey),

        const SizedBox(height: 40),
        const Text('Berapa kali sehari?', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 20),

        // Slider 1–6 kali
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (i) {
            int kali = i + 1;
            return GestureDetector(
              onTap: () => setState(() => _timesPerDay = kali),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _timesPerDay == kali ? Colors.blue : const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$kali×',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _timesPerDay == kali ? Colors.white : Colors.grey,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '$_timesPerDay kali sehari',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
          ),
        ),

        const SizedBox(height: 50),

        // Jumlah Tablet
        const Text('Jumlah tablet / strip', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 10),
        TextField(
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 24),
          decoration: InputDecoration(
            hintText: '$_totalTablets',
            hintStyle: const TextStyle(color: Colors.grey),
            border: InputBorder.none,
          ),
          onChanged: (v) => _totalTablets = int.tryParse(v) ?? 30,
        ),
        const Divider(color: Colors.grey),

        const SizedBox(height: 40),

        // Jenis Notifikasi
        const Text('Jenis pengingat', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Notifikasi biasa saja'),
          value: _notificationOnly,
          activeColor: Colors.blue,
          onChanged: (v) => setState(() => _notificationOnly = v),
        ),
        SwitchListTile(
          title: const Text('Alarm dengan suara'),
          value: _alarmSound,
          activeColor: Colors.blue,
          onChanged: (v) => setState(() => _alarmSound = v),
        ),
      ]),
    );
  }
}