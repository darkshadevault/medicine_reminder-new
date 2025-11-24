// lib/main.dart  ← GANTI FILE INI SAJA! TIDAK PERLU FILE ALARM!

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

final FlutterLocalNotificationsPlugin notif = FlutterLocalNotificationsPlugin();

Future<void> initNotif() async {
  tz.initializeTimeZones();
  final String tzName = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(tzName));

  const AndroidInitializationSettings android =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await notif.initialize(const InitializationSettings(android: android));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotif();
  runApp(const MedicineReminderApp());
}

class MedicineReminderApp extends StatelessWidget {
  const MedicineReminderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pengingat Minum Obat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black, elevation: 0),
      ),
      home: const ReminderHomePage(),
    );
  }
}

class ReminderHomePage extends StatefulWidget {
  const ReminderHomePage({super.key});
  @override
  State<ReminderHomePage> createState() => _ReminderHomePageState();
}

class _ReminderHomePageState extends State<ReminderHomePage> {
  List<Map<String, dynamic>> reminders = [];
  final Set<int> selected = {};

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? data = prefs.getStringList('reminders');
    if (data != null) {
      setState(() {
        reminders = data.map((e) {
          final parts = e.split('|');
          return {
            'name': parts[0],
            'freq': int.parse(parts[1]),
            'doses': int.parse(parts[2]),
            'time': DateTime.parse(parts[3]),
            'alarm': parts[4] == 'true',
          };
        }).toList();
      });
    }
  }

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> data = reminders.map((r) =>
        '${r['name']}|${r['freq']}|${r['doses']}|${r['time'].toIso8601String()}|${r['alarm']}').toList();
    await prefs.setStringList('reminders', data);
  }

  Future<void> _addReminder() async {
    // 1. Pilih jam (besar seperti gambar kamu)
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark(),
        child: child!,
      ),
    );
    if (picked == null) return;

    final DateTime selectedTime = DateTime(2025, 1, 1, picked.hour, picked.minute);

    // 2. Input nama obat
    String name = '';
    final nameOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Nama Obat'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Paracetamol'),
          style: const TextStyle(color: Colors.white),
          onChanged: (v) => name = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (nameOk != true || name.trim().isEmpty) return;
    name = name.trim();

    // 3. Pilih frekuensi
    int freq = 1;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Minum berapa kali sehari?', style: TextStyle(fontSize: 18, color: Colors.white)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: List.generate(6, (i) {
                  final val = i + 1;
                  return ChoiceChip(
                    label: Text('$val kali', style: const TextStyle(color: Colors.white)),
                    selected: freq == val,
                    selectedColor: Colors.blue,
                    onSelected: (_) => setSheet(() => freq = val),
                  );
                }),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );

    // 4. Jumlah dosis
    final doseCtrl = TextEditingController(text: '30');
    int doses = 30;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Jumlah Dosis'),
        content: TextField(
          controller: doseCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '30', suffixText: ' tablet'),
          style: const TextStyle(color: Colors.white),
          onChanged: (v) => doses = int.tryParse(v) ?? 30,
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );

    // 5. Alarm atau notifikasi
    bool useAlarm = true;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Pilih suara'),
        actions: [
          TextButton(
            onPressed: () { useAlarm = false; Navigator.pop(context); },
            child: const Text('Notifikasi saja'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Alarm (suara + getar)'),
          ),
        ],
      ),
    );

    // Simpan & jadwalkan
    reminders.add({'name': name, 'time': selectedTime, 'freq': freq, 'doses': doses, 'alarm': useAlarm});
    await _saveReminders();
    await _scheduleNotifications(name, selectedTime, freq, doses, useAlarm);
    setState(() {});
  }

  Future<void> _scheduleNotifications(String name, DateTime time, int freq, int doses, bool useAlarm) async {
    await notif.cancelAll();
    final double interval = 24.0 / freq;
    DateTime first = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, time.hour, time.minute);
    if (first.isBefore(DateTime.now())) first = first.add(const Duration(days: 1));

    for (int i = 0; i < doses; i++) {
      final DateTime dt = first.add(Duration(minutes: (i * interval * 60).round()));
      await notif.zonedSchedule(
        dt.millisecondsSinceEpoch ~/ 1000,
        'Waktunya minum $name',
        'Jangan lupa minum obat!',
        tz.TZDateTime.from(dt, tz.local),
        AndroidNotificationDetails(
          'medicine',
          'Pengingat Obat',
          importance: Importance.max,
          priority: Priority.high,
          playSound: useAlarm,
          enableVibration: useAlarm,
          // TIDAK PAKAI FILE ALARM → pakai suara default Android
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  void _deleteSelected() async {
    final sorted = selected.toList()..sort((a, b) => b.compareTo(a));
    for (int i in sorted) reminders.removeAt(i);
    await notif.cancelAll();
    await _saveReminders();
    setState(() => selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengingat Minum Obat'),
        actions: selected.isNotEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(child: Text('${selected.length} item terpilih', style: const TextStyle(color: Colors.white70))),
                ),
                IconButton(icon: const Icon(Icons.delete), onPressed: _deleteSelected),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => selected.clear())),
              ]
            : null,
      ),
      body: reminders.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.medication, size: 90, color: Colors.grey),
                  SizedBox(height: 20),
                  Text('Belum ada pengingat', style: TextStyle(fontSize: 20, color: Colors.grey)),
                  Text('Tekan + untuk menambah', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: reminders.length,
              itemBuilder: (ctx, i) {
                final r = reminders[i];
                final isSelected = selected.contains(i);
                return Dismissible(
                  key: ValueKey(i),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 30),
                    child: const Icon(Icons.delete, color: Colors.white, size: 30),
                  ),
                  onDismissed: (_) async {
                    reminders.removeAt(i);
                    await notif.cancelAll();
                    await _saveReminders();
                    setState(() {});
                  },
                  child: ListTile(
                    selected: isSelected,
                    selectedTileColor: Colors.blue.withOpacity(0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    title: Text(r['name'], style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500)),
                    subtitle: Text('${r['freq']} kali sehari • ${r['doses']} dosis'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(DateFormat('HH:mm').format(r['time']), style: const TextStyle(fontSize: 36)),
                        Text(r['alarm'] ? 'Alarm' : 'Notifikasi', style: TextStyle(color: r['alarm'] ? Colors.blue : Colors.grey)),
                      ],
                    ),
                    onTap: selected.isNotEmpty
                        ? () => setState(() => isSelected ? selected.remove(i) : selected.add(i))
                        : null,
                    onLongPress: () => setState(() => selected.add(i)),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue,
        onPressed: _addReminder,
        child: const Icon(Icons.add, size: 32),
      ),
    );
  }
}