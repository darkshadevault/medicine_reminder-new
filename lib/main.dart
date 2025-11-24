// lib/main.dart → GANTI SEMUA DENGAN INI! VERSI PALING BERSIH & KEREN

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
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('reminders') ?? [];
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

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = reminders
        .map((r) => '\( {r['name']}| \){r['freq']}|\( {r['doses']}| \){r['time'].toIso8601String()}|${r['alarm']}')
        .toList();
    await prefs.setStringList('reminders', data);
  }

  Future<void> _addReminder() async {
    // 1. Pilih jam
    final tod = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (_, child) => Theme(data: ThemeData.dark(), child: child!),
    );
    if (tod == null) return;
    final time = DateTime(2025, 1, 1, tod.hour, tod.minute);

    // 2. Nama obat
    String name = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nama Obat'),
        content: TextField(
          autofocus: true,
          style: const TextStyle(fontSize: 18, color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Paracetamol',
            border: UnderlineInputBorder(),
          ),
          onChanged: (v) => name = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lanjut', style: TextStyle(color: Colors.blue))),
        ],
      ),
    );
    if (ok != true || name.trim().isEmpty) return;
    name = name.trim();

    // 3. Frekuensi — SCROLL WHEEL BESAR
    int freq = 1;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        height: 380,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text('Berapa kali sehari?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ListWheelScrollView.useDelegate(
                itemExtent: 70,
                physics: const FixedExtentScrollPhysics(),
                diameterRatio: 1.8,
                onSelectedItemChanged: (i) => freq = i + 1,
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: 6,
                  builder: (_, i) => Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, minimumSize: const Size(double.infinity, 52)),
                child: const Text('OK', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );

    // 4. Jumlah dosis — kosong
    final doseCtrl = TextEditingController();
    int doses = 30;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Jumlah Dosis'),
        content: TextField(
          controller: doseCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
          decoration: const InputDecoration(hintText: '30', border: InputBorder.none),
          onChanged: (v) => doses = int.tryParse(v) ?? 1,
        ),
        actions: [Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Colors.blue, fontSize: 18))))],
      ),
    );
    if (doses < 1) doses = 1;

    // 5. Alarm keras → SWITCH ON/OFF
    bool useAlarm = true;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Alarm keras + getar', style: TextStyle(fontSize: 18, color: Colors.white)),
            Switch(value: useAlarm, activeColor: Colors.blue, onChanged: (v) => setState(() => useAlarm = v)),
          ],
        ),
        actions: [Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Selesai', style: TextStyle(color: Colors.blue, fontSize: 18))))],
      ),
    );

    // Simpan & jadwalkan
    reminders.add({'name': name, 'time': time, 'freq': freq, 'doses': doses, 'alarm': useAlarm});
    await _save();
    await _schedule(name, time, freq, doses, useAlarm);
    setState(() {});
  }

  Future<void> _schedule(String name, DateTime time, int freq, int doses, bool useAlarm) async {
    await notif.cancelAll();
    final interval = 24.0 / freq;
    var first = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, time.hour, time.minute);
    if (first.isBefore(DateTime.now())) first = first.add(const Duration(days: 1));

    for (int i = 0; i < doses; i++) {
      final dt = first.add(Duration(minutes: (i * interval * 60).round()));
      await notif.zonedSchedule(
        dt.millisecondsSinceEpoch ~/ 1000,
        'Waktunya minum $name',
        'Jangan lupa minum obat!',
        tz.TZDateTime.from(dt, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'medicine', 'Pengingat Obat',
            importance: Importance.max,
            priority: Priority.high,
            playSound: useAlarm,
            enableVibration: useAlarm,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  void _deleteSelected() async {
    final sorted = selected.toList()..sort((a, b) => b.compareTo(a));
    for (final i in sorted) reminders.removeAt(i);
    await notif.cancelAll();
    await _save();
    setState(() => selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengingat Minum Obat', style: TextStyle(fontSize: 21)),
        actions: selected.isNotEmpty
            ? [
                Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: Text('${selected.length} dipilih', style: TextStyle(color: Colors.white70)))),
                IconButton(icon: const Icon(Icons.delete), onPressed: _deleteSelected),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => selected.clear())),
              ]
            : null,
      ),
      body: reminders.isEmpty
          ? const SizedBox() // KOSONG TOTAL! Hanya background hitam + tombol +
          : ListView.builder(
              itemCount: reminders.length,
              itemBuilder: (_, i) {
                final r = reminders[i];
                final sel = selected.contains(i);
                return Dismissible(
                  key: ValueKey(i),
                  direction: DismissDirection.endToStart,
                  background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 30), child: const Icon(Icons.delete, color: Colors.white, size: 34)),
                  onDismissed: (_) async {
                    reminders.removeAt(i);
                    await notif.cancelAll();
                    await _save();
                    setState(() {});
                  },
                  child: ListTile(
                    selected: sel,
                    selectedTileColor: Colors.blue.withOpacity(0.25),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                    title: Text(r['name'], style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
                    subtitle: Text('\( {r['freq']} kali sehari • \){r['doses']} dosis', style: const TextStyle(fontSize: 16)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(DateFormat('HH:mm').format(r['time']), style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold)),
                        Text(r['alarm'] ? 'Alarm' : 'Notifikasi', style: TextStyle(fontSize: 15, color: r['alarm'] ? Colors.blue : Colors.grey)),
                      ],
                    ),
                    onTap: selected.isNotEmpty ? () => setState(() => sel ? selected.remove(i) : selected.add(i)) : null,
                    onLongPress: () => setState(() => selected.add(i)),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue,
        elevation: 10,
        child: const Icon(Icons.add, size: 36),
        onPressed: _addReminder,
      ),
    );
  }
}