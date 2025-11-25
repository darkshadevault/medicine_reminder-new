import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
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
  await notifications.initialize(const InitializationSettings(android: android));

  runApp(const MedicineReminderApp());
}

class Medicine {
  String id;
  String name;
  int timesPerDay;
  int totalDoses;
  int remainingDoses;
  TimeOfDay firstDoseTime;
  bool notificationOnly;
  bool alarmSound;
  bool isActive;

  Medicine({
    required this.id,
    required this.name,
    required this.timesPerDay,
    required this.totalDoses,
    required this.firstDoseTime,
    this.notificationOnly = true,
    this.alarmSound = false,
    this.isActive = true,
  }) : remainingDoses = totalDoses;

  double get daysLeft => remainingDoses / timesPerDay;
  String get remainingText {
    final days = daysLeft.floor();
    final hours = ((daysLeft - days) * 24).round();
    if (days == 0) return '$hours jam lagi';
    if (hours == 0) return '$days hari lagi';
    return '$days hari $hours jam lagi';
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'timesPerDay': timesPerDay, 'totalDoses': totalDoses,
        'remainingDoses': remainingDoses, 'firstDoseHour': firstDoseTime.hour,
        'firstDoseMinute': firstDoseTime.minute, 'notificationOnly': notificationOnly,
        'alarmSound': alarmSound, 'isActive': isActive,
      };

  factory Medicine.fromJson(Map<String, dynamic> json) => Medicine(
        id: json['id'],
        name: json['name'],
        timesPerDay: json['timesPerDay'],
        totalDoses: json['totalDoses'],
        firstDoseTime: TimeOfDay(hour: json['firstDoseHour'] ?? 8, minute: json['firstDoseMinute'] ?? 0),
        notificationOnly: json['notificationOnly'] ?? true,
        alarmSound: json['alarmSound'] ?? false,
        isActive: json['isActive'] ?? true,
      )..remainingDoses = json['remainingDoses'] ?? json['totalDoses'];
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
        medicines = (jsonDecode(data) as List).map((e) => Medicine.fromJson(e)).toList();
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
    _scheduleAll(m);
  }

  void _toggle(Medicine m) {
    setState(() => m.isActive = !m.isActive);
    _save();
    m.isActive ? _scheduleAll(m) : _cancelAll(m);
  }

  Future<void> _scheduleAll(Medicine m) async {
    await _cancelAll(m);
    final intervalHours = 24.0 / m.timesPerDay;
    var currentTime = DateTime.now();
    var baseTime = DateTime(currentTime.year, currentTime.month, currentTime.day,
        m.firstDoseTime.hour, m.firstDoseTime.minute);

    if (baseTime.isBefore(currentTime)) {
      baseTime = baseTime.add(const Duration(days: 1));
    }

    int doseCount = 0;
    while (doseCount < m.remainingDoses) {
      for (int i = 0; i < m.timesPerDay && doseCount < m.remainingDoses; i++) {
        final scheduledTime = baseTime.add(Duration(minutes: (i * intervalHours * 60).round()));
        await notifications.zonedSchedule(
          int.parse('${m.id}_$doseCount'),
          'Waktunya Minum Obat!',
          '${m.name} • Dosis ${doseCount + 1}',
          tz.TZDateTime.from(scheduledTime, tz.local),
          const NotificationDetails(android: AndroidNotificationDetails('med', 'Obat', importance: Importance.max, priority: Priority.high)),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
        doseCount++;
      }
      baseTime = baseTime.add(const Duration(days: 1));
    }
  }

  Future<void> _cancelAll(Medicine m) async {
    for (int i = 0; i < 1000; i++) await notifications.cancel(int.parse('${m.id}_$i'));
  }

  List<Map<String, dynamic>> getNextThreeDaysSchedule(Medicine m) {
    final List<Map<String, dynamic>> schedule = [];
    final intervalHours = 24.0 / m.timesPerDay;
    var currentTime = DateTime.now();
    var baseTime = DateTime(currentTime.year, currentTime.month, currentTime.day,
        m.firstDoseTime.hour, m.firstDoseTime.minute);

    if (baseTime.isBefore(currentTime)) baseTime = baseTime.add(const Duration(days: 1));

    int doseCount = 0;
    for (int day = 0; day < 3 && doseCount < m.remainingDoses; day++) {
      final dayDate = baseTime.add(Duration(days: day));
      final dayName = day == 0 ? 'Hari ini' : day == 1 ? 'Besok' : 'Lusa';
      final dateStr = DateFormat('EEE, d MMM').format(dayDate);
      final List<String> times = [];

      for (int i = 0; i < m.timesPerDay && doseCount < m.remainingDoses; i++) {
        final time = dayDate.add(Duration(minutes: (i * intervalHours * 60).round()));
        times.add(DateFormat('HH:mm').format(time));
        doseCount++;
      }
      schedule.add({'day': dayName, 'date': dateStr, 'times': times});
    }
    return schedule;
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
                final schedule = getNextThreeDaysSchedule(m);

                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D1D1D),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(m.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          Switch(value: m.isActive, activeColor: Colors.blue, onChanged: (_) => _toggle(m)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('${m.timesPerDay}× sehari • Mulai ${m.firstDoseTime.format(context)}', style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 12),
                      Text('Sisa ${m.remainingDoses} dosis • ${m.remainingText}', style: const TextStyle(color: Colors.green, fontSize: 16)),
                      const Divider(color: Colors.grey, height: 30),

                      const Text('Jadwal 3 hari ke depan:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      ...schedule.map((day) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            SizedBox(width: 100, child: Text(day['day'], style: const TextStyle(fontWeight: FontWeight.w500))),
                            Text(day['date'], style: const TextStyle(color: Colors.grey)),
                            const Spacer(),
                            Text(day['times'].join('   •   '), style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                      )).toList(),
                    ],
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

// HALAMAN TAMBAH OBAT (tetap sama seperti sebelumnya, sudah benar)
class AddMedicineScreen extends StatefulWidget {
  final Function(Medicine) onSave;
  const AddMedicineScreen({super.key, required this.onSave});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _nameController = TextEditingController();
  int _timesPerDay = 3;
  int _totalDoses = 10;
  TimeOfDay _firstDoseTime = const TimeOfDay(hour: 8, minute: 0);
  bool _notifOnly = true;
  bool _alarm = false;

  final frequencies = [
    {'times': 1, 'text': '1 kali sehari', 'interval': '24 jam'},
    {'times': 2, 'text': '2 kali sehari', 'interval': '12 jam'},
    {'times': 3, 'text': '3 kali sehari', 'interval': '8 jam'},
    {'times': 4, 'text': '4 kali sehari', 'interval': '6 jam'},
    {'times': 5, 'text': '5 kali sehari', 'interval': '≈4.8 jam'},
    {'times': 6, 'text': '6 kali sehari', 'interval': '4 jam'},
  ];

  @override
  Widget build(BuildContext context) {
    final selected = frequencies.firstWhere((e) => e['times'] == _timesPerDay);
    final daysLeft = _totalDoses / _timesPerDay;
    final days = daysLeft.floor();
    final hours = ((daysLeft - days) * 24).round();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal', style: TextStyle(color: Colors.grey))),
        actions: [TextButton(
          onPressed: _nameController.text.trim().isEmpty ? null : () {
            final med = Medicine(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: _nameController.text.trim(),
              timesPerDay: _timesPerDay,
              totalDoses: _totalDoses,
              firstDoseTime: _firstDoseTime,
              notificationOnly: _notifOnly,
              alarmSound: _alarm,
            );
            widget.onSave(med);
            Navigator.pop(context);
          },
          child: const Text('Simpan', style: TextStyle(color: Colors.blue)),
        )],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Nama obat', style: TextStyle(fontSize: 17)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: TextField(controller: _nameController, style: const TextStyle(color: Colors.black, fontSize: 18),
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Paracetamol, Amoxicillin, dll'),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Total berapa kali harus minum obat ini?', style: TextStyle(fontSize: 17)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: TextField(
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.black, fontSize: 18),
            decoration: InputDecoration(border: InputBorder.none, hintText: '$_totalDoses kali minum'),
            onChanged: (v) => setState(() => _totalDoses = int.tryParse(v) ?? 10),
          ),
        ),
        const SizedBox(height: 32),
        const Text('Jam pertama minum hari ini', style: TextStyle(fontSize: 17)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: _firstDoseTime, builder: (_, child) => Theme(data: ThemeData.dark(), child: child!));
            if (t != null) setState(() => _firstDoseTime = t);
          },
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF1D1D1D), borderRadius: BorderRadius.circular(16)),
            child: Center(child: Text(_firstDoseTime.format(context), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300))),
          ),
        ),
        const SizedBox(height: 40),
        const Text('Berapa kali sehari?', style: TextStyle(fontSize: 17)),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: CupertinoPicker(
            itemExtent: 44,
            magnification: 1.2,
            useMagnifier: true,
            onSelectedItemChanged: (i) => setState(() => _timesPerDay = frequencies[i]['times'] as int),
            children: frequencies.map((f) => Center(child: Text(f['text'] as String, style: const TextStyle(fontSize: 22)))).toList(),
          ),
        ),
        Center(child: Text('Setiap ${selected['interval']}', style: const TextStyle(fontSize: 18, color: Colors.grey))),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'Total durasi: $days hari ${hours > 0 ? '$hours jam' : ''}\n($_totalDoses kali ÷ $_timesPerDay kali/hari)',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.white70),
          ),
        ),
        const SizedBox(height: 40),
        const Text('Jenis pengingat', style: TextStyle(fontSize: 17)),
        SwitchListTile(title: const Text('Notifikasi biasa'), value: _notifOnly, onChanged: (v) => setState(() => _notifOnly = v)),
        SwitchListTile(title: const Text('Alarm dengan suara'), value: _alarm, onChanged: (v) => setState(() => _alarm = v)),
      ]),
    );
  }
}
