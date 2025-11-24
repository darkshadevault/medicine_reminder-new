// lib/main.dart → GANTI SELURUHNYA DENGAN INI! 100% JALAN!

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
          final p = e.split('|');
          return {
            'name': p[0],
            'freq': int.parse(p[1]),
            'doses': int.parse(p[2]),
            'time': DateTime.parse(p[3]),
            'alarm': p[4] == 'true',
          };
        }).toList();
      });
    }
  }

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final data = reminders
        .map((r) =>
            '${r['name']}|${r['freq']}|${r['doses']}|${r['time'].toIso8601String()}|${r['alarm']}')
        .toList();
    await prefs.setStringList('reminders', data);
  }

  Future<void> _addReminder() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (_, child) => Theme(data: ThemeData.dark(), child: child!),
    );
    if (picked == null) return;

    final time = DateTime(2025, 1, 1, picked.hour, picked.minute);

    String name = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Nama Obat'),
        content: TextField(autofocus: true, onChanged: (v) => name = v),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true || name.trim().isEmpty) return;
    name = name.trim();

    int freq = 1;
    await showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => Container(
          color: Colors.grey[900],
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Berapa kali sehari?', style: TextStyle(fontSize: 18, color: Colors.white)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              children: List.generate(6, (i) {
                final v = i + 1;
                return ChoiceChip(
                  label: Text('$v kali'),
                  selected: freq == v,
                  onSelected: (_) => set(() => freq = v),
                );
              }),
            ),
          ]),
        ),
      ),
    );

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
          onChanged: (v) => doses = int.tryParse(v) ?? 30,
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );

    bool useAlarm = true;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Pilih jenis pengingat'),
        actions: [
          TextButton(onPressed: () { useAlarm = false; Navigator.pop(context); }, child: const Text('Notifikasi saja')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Alarm keras')),
        ],
      ),
    );

    reminders.add({'name': name, 'time': time, 'freq': freq, 'doses': doses, 'alarm': useAlarm});
    await _saveReminders();
    await _scheduleAll(name, time, freq, doses, useAlarm);
    setState(() {});
  }

  Future<void> _scheduleAll(String name, DateTime time, int freq, int doses, bool useAlarm) async {
    await notif.cancelAll();
    final interval = 24.0 / freq;
    DateTime first = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, time.hour, time.minute);
    if (first.isBefore(DateTime.now())) first = first.add(const Duration(days: 1));

    for (int i = 0; i < doses; i++) {
      final dt = first.add(Duration(minutes: (i * interval * 60).round()));
      final androidDetails = AndroidNotificationDetails(
        'medicine',
        'Pengingat Minum Obat',
        importance: Importance.max,
        priority: Priority.high,
        playSound: useAlarm,
        enableVibration: useAlarm,
      );

      // PERBAIKAN UTAMA: Pakai NotificationDetails(android: ...)
      await notif.zonedSchedule(
        dt.millisecondsSinceEpoch ~/ 1000,
        'Waktunya minum $name',
        'Jangan lupa minum obat!',
        tz.TZDateTime.from(dt, tz.local),
        NotificationDetails(android: androidDetails), // INI YANG DIPERBAIKI
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  void _deleteSelected() async {
    final sorted = selected.toList()..sort((a, b) => b.compareTo(a));
    for (final i in sorted) reminders.removeAt(i);
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
                Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: Text('${selected.length} item'))),
                IconButton(icon: const Icon(Icons.delete), onPressed: _deleteSelected),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => selected.clear())),
              ]
            : null,
      ),
      body: reminders.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.medication, size: 90, color: Colors.grey),
              SizedBox(height: 20),
              Text('Belum ada pengingat', style: TextStyle(fontSize: 20, color: Colors.grey)),
              Text('Tekan + untuk tambah', style: TextStyle(color: Colors.grey)),
            ]))
          : ListView.builder(
              itemCount: reminders.length,
              itemBuilder: (_, i) {
                final r = reminders[i];
                final sel = selected.contains(i);
                return Dismissible(
                  key: ValueKey(i),
                  direction: DismissDirection.endToStart,
                  background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 30), child: const Icon(Icons.delete, color: Colors.white, size: 30)),
                  onDismissed: (_) async {
                    reminders.removeAt(i);
                    await notif.cancelAll();
                    await _saveReminders();
                    setState(() {});
                  },
                  child: ListTile(
                    selected: sel,
                    selectedTileColor: Colors.blue.withOpacity(0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    title: Text(r['name'], style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500)),
                    subtitle: Text('${r['freq']} kali sehari • ${r['doses']} dosis'),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(DateFormat('HH:mm').format(r['time']), style: const TextStyle(fontSize: 36)),
                      Text(r['alarm'] ? 'Alarm' : 'Notif', style: TextStyle(color: r['alarm'] ? Colors.blue : Colors.grey)),
                    ]),
                    onTap: selected.isNotEmpty ? () => setState(() => sel ? selected.remove(i) : selected.add(i)) : null,
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
