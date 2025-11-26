import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/date_symbol_data_local.dart';
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
  await notifications.initialize(
    const InitializationSettings(android: android),
    onDidReceiveNotificationResponse: (response) {
      if (response.payload != null) {
        final parts = response.payload!.split('|');
        if (parts.length == 2) {
          _markDoseAsTaken(parts[0], int.parse(parts[1]));
        }
      }
    },
  );

  await initializeDateFormatting('id_ID', null);
  runApp(const MedicineReminderApp());
}

Future<void> _markDoseAsTaken(String medId, int doseIndex) async {
  final prefs = await SharedPreferences.getInstance();
  final data = prefs.getString('medicines') ?? '[]';
  final List medicines = jsonDecode(data);

  for (var m in medicines) {
    if (m['id'] == medId) {
      final takenKey = 'taken_$medId';
      final taken = prefs.getStringList(takenKey) ?? [];
      final key = doseIndex.toString();
      if (!taken.contains(key)) {
        taken.add(key);
        await prefs.setStringList(takenKey, taken);
        if (m['remainingDoses'] > 0) {
          m['remainingDoses']--;
          await prefs.setString('medicines', jsonEncode(medicines));
        }
      }
      break;
    }
  }
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
        'id': id,
        'name': name,
        'timesPerDay': timesPerDay,
        'totalDoses': totalDoses,
        'remainingDoses': remainingDoses,
        'firstDoseHour': firstDoseTime.hour,
        'firstDoseMinute': firstDoseTime.minute,
        'notificationOnly': notificationOnly,
        'alarmSound': alarmSound,
        'isActive': isActive,
      };

  factory Medicine.fromJson(Map<String, dynamic> json) {
    final m = Medicine(
      id: json['id'],
      name: json['name'],
      timesPerDay: json['timesPerDay'],
      totalDoses: json['totalDoses'],
      firstDoseTime: TimeOfDay(
        hour: json['firstDoseHour'] ?? 8,
        minute: json['firstDoseMinute'] ?? 0,
      ),
      notificationOnly: json['notificationOnly'] ?? true,
      alarmSound: json['alarmSound'] ?? false,
      isActive: json['isActive'] ?? true,
    );
    m.remainingDoses = json['remainingDoses'] ?? json['totalDoses'];
    return m;
  }
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
    _loadAndReschedule();
  }

  Future<void> _loadAndReschedule() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('medicines');
    if (data != null) {
      medicines = (jsonDecode(data) as List).map((e) => Medicine.fromJson(e)).toList();
      for (final m in medicines.where((m) => m.isActive)) {
        await _scheduleAll(m);
      }
    }
    setState(() {});
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('medicines', jsonEncode(medicines.map((e) => e.toJson()).toList()));
  }

  void _add(Medicine m) {
    setState(() => medicines.add(m));
    _save();
    if (m.isActive) _scheduleAll(m);
  }

  void _update(Medicine updated) async {
    final index = medicines.indexWhere((m) => m.id == updated.id);
    if (index != -1) {
      await _cancelAll(medicines[index]);
      medicines[index] = updated;
      _save();
      if (updated.isActive) await _scheduleAll(updated);
      setState(() {});
    }
  }

  Future<void> _delete(Medicine m) async {
    await _cancelAll(m);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('taken_${m.id}');
    setState(() => medicines.remove(m));
    _save();
  }

  Future<void> _scheduleAll(Medicine m) async {
    await _cancelAll(m);
    if (!m.isActive || m.remainingDoses <= 0) return;

    final intervalMinutes = (1440 / m.timesPerDay).floor();
    var now = DateTime.now();
    var todayFirst = DateTime(now.year, now.month, now.day, m.firstDoseTime.hour, m.firstDoseTime.minute);
    if (todayFirst.isBefore(now)) todayFirst = todayFirst.add(const Duration(days: 1));

    final prefs = await SharedPreferences.getInstance();
    final takenSet = prefs.getStringList('taken_${m.id}')?.map(int.parse).toSet() ?? {};

    int doseIndex = 0;
    while (doseIndex < m.totalDoses) {
      final dayOffset = (doseIndex / m.timesPerDay).floor();
      final dayBase = todayFirst.add(Duration(days: dayOffset));

      for (int i = 0; i < m.timesPerDay && doseIndex < m.totalDoses; i++) {
        if (takenSet.contains(doseIndex)) {
          doseIndex++;
          continue;
        }

        final scheduledTime = dayBase.add(Duration(minutes: i * intervalMinutes));
        final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
        final notifId = int.parse(m.id) + doseIndex;

        await notifications.zonedSchedule(
          notifId,
          'Waktunya Minum Obat!',
          '\( {m.name} • Dosis \){doseIndex + 1}',
          tzTime,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'med',
              'Pengingat Obat',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: '${m.id}|$doseIndex',
        );
        doseIndex++;
      }
    }
  }

  Future<void> _cancelAll(Medicine m) async {
    for (int i = 0; i < m.totalDoses; i++) {
      await notifications.cancel(int.parse(m.id) + i);
    }
  }

  List<Map<String, dynamic>> getNextThreeDaysSchedule(Medicine m) {
    final schedule = <Map<String, dynamic>>[];
    final intervalMinutes = (1440 / m.timesPerDay).floor();
    var now = DateTime.now();
    var todayFirst = DateTime(now.year, now.month, now.day, m.firstDoseTime.hour, m.firstDoseTime.minute);
    if (todayFirst.isBefore(now)) todayFirst = todayFirst.add(const Duration(days: 1));

    for (int day = 0; day < 3; day++) {
      final date = todayFirst.add(Duration(days: day));
      final dayName = day == 0 ? 'Hari ini' : day == 1 ? 'Besok' : 'Lusa';
      final dateStr = DateFormat('EEE, d MMM', 'id_ID').format(date);
      final times = <String>[];
      for (int i = 0; i < m.timesPerDay; i++) {
        final t = date.add(Duration(minutes: i * intervalMinutes));
        times.add(DateFormat('HH:mm').format(t));
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

                return Dismissible(
                  key: Key(m.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white, size: 32),
                  ),
                  confirmDismiss: (_) async {
                    final confirm = await showCupertinoDialog<bool>(
                      context: context,
                      builder: (_) => CupertinoAlertDialog(
                        title: const Text('Hapus Obat?'),
                        content: Text('Yakin ingin hapus "${m.name}"?'),
                        actions: [
                          CupertinoDialogAction(child: const Text('Batal'), onPressed: () => Navigator.pop(context, false)),
                          CupertinoDialogAction(
                            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                            isDestructiveAction: true,
                            onPressed: () => Navigator.pop(context, true),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      _delete(m);
                      return true;
                    }
                    return false;
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: const Color(0xFF1D1D1D), borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(m.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => Navigator.push(
                                    context,
                                    CupertinoPageRoute(builder: (_) => AddMedicineScreen(onSave: _update, medicineToEdit: m)),
                                  ),
                                ),
                                Switch(
                                  value: m.isActive,
                                  activeColor: Colors.blue,
                                  onChanged: (val) async {
                                    setState(() => m.isActive = val);
                                    await _save();
                                    if (val) {
                                      await _scheduleAll(m);
                                    } else {
                                      await _cancelAll(m);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('\( {m.timesPerDay}× sehari • Mulai \){m.firstDoseTime.format(context)}', style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 12),
                        Text('Sisa \( {m.remainingDoses} dosis • \){m.remainingText}', style: const TextStyle(color: Colors.green, fontSize: 16)),
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
                            )),
                      ],
                    ),
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

class AddMedicineScreen extends StatefulWidget {
  final Function(Medicine) onSave;
  final Medicine? medicineToEdit;
  const AddMedicineScreen({super.key, required this.onSave, this.medicineToEdit});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  late TextEditingController _nameController;
  late int _timesPerDay;
  late int _totalDoses;
  late TimeOfDay _firstDoseTime;
  late bool _notifOnly;
  late bool _alarm;

  final frequencies = [
    {'times': 1, 'text': '1 kali sehari', 'interval': '24 jam'},
    {'times': 2, 'text': '2 kali sehari', 'interval': '12 jam'},
    {'times': 3, 'text': '3 kali sehari', 'interval': '8 jam'},
    {'times': 4, 'text': '4 kali sehari', 'interval': '6 jam'},
    {'times': 5, 'text': '5 kali sehari', 'interval': '≈4 jam 48 mnt'},
    {'times': 6, 'text': '6 kali sehari', 'interval': '4 jam'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.medicineToEdit != null) {
      final m = widget.medicineToEdit!;
      _nameController = TextEditingController(text: m.name);
      _timesPerDay = m.timesPerDay;
      _totalDoses = m.totalDoses;
      _firstDoseTime = m.firstDoseTime;
      _notifOnly = m.notificationOnly;
      _alarm = m.alarmSound;
    } else {
      _nameController = TextEditingController();
      _timesPerDay = 3;
      _totalDoses = 30;
      _firstDoseTime = const TimeOfDay(hour: 8, minute: 0);
      _notifOnly = true;
      _alarm = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = frequencies.firstWhere((e) => e['times'] == _timesPerDay);
    final days = (_totalDoses / _timesPerDay).floor();
    final hours = ((_totalDoses / _timesPerDay - days) * 24).round();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal', style: TextStyle(color: Colors.grey)),
        ),
        title: Text(widget.medicineToEdit != null ? 'Edit Obat' : 'Tambah Obat'),
        actions: [
          TextButton(
            onPressed: _nameController.text.trim().isEmpty
                ? null
                : () {
                    final med = Medicine(
                      id: widget.medicineToEdit?.id ?? Random().nextInt(999999).toString().padLeft(6, '0'),
                      name: _nameController.text.trim(),
                      timesPerDay: _timesPerDay,
                      totalDoses: _totalDoses,
                      firstDoseTime: _firstDoseTime,
                      notificationOnly: _notifOnly,
                      alarmSound: _alarm,
                      isActive: widget.medicineToEdit?.isActive ?? true,
                    );
                    widget.onSave(med);
                    Navigator.pop(context);
                  },
            child: const Text('Simpan', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Nama obat', style: TextStyle(fontSize: 17)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.black, fontSize: 18),
              decoration: const InputDecoration(border: InputBorder.none, hintText: 'Paracetamol'),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Total dosis', style: TextStyle(fontSize: 17)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: TextField(
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.black, fontSize: 18),
              decoration: InputDecoration(border: InputBorder.none, hintText: '30 dosis'),
              onChanged: (v) => setState(() => _totalDoses = int.tryParse(v) ?? 30),
            ),
          ),
          const SizedBox(height: 32),
          const Text('Jam pertama hari ini', style: TextStyle(fontSize: 17)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: _firstDoseTime,
                builder: (_, child) => Theme(data: ThemeData.dark(), child: child!),
              );
              if (t != null) setState(() => _firstDoseTime = t);
            },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1D1D1D), borderRadius: BorderRadius.circular(16)),
              child: Center(
                child: Text(
                  _firstDoseTime.format(context),
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300),
                ),
              ),
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
              children: frequencies
                  .map((f) => Center(child: Text(f['text'] as String, style: const TextStyle(fontSize: 22))))
                  .toList(),
            ),
          ),
          Center(child: Text('Setiap ${selected['interval']}', style: const TextStyle(fontSize: 18, color: Colors.grey))),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Durasi ≈ \( days hari \){hours > 0 ? ' $hours jam' : ''}',
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 40),
          const Text('Jenis pengingat', style: TextStyle(fontSize: 17)),
          SwitchListTile(title: const Text('Hanya notifikasi (tanpa suara)'), value: _notifOnly, onChanged: (v) => setState(() => _notifOnly = v)),
          SwitchListTile(title: const Text('Alarm keras'), value: _alarm, onChanged: (v) => setState(() => _alarm = v)),
        ],
      ),
    );
  }
}