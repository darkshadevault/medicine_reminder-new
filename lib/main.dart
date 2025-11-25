import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(const MedicineReminderApp());
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class MedicineReminderApp extends StatelessWidget {
  const MedicineReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
      ),
      home: const MedicineListScreen(),
    );
  }
}

class Medicine {
  String name;
  int timesPerDay;
  int totalTablets;
  bool notificationOnly;
  bool alarmSound;
  bool isActive;

  Medicine({
    required this.name,
    required this.timesPerDay,
    required this.totalTablets,
    this.notificationOnly = true,
    this.alarmSound = false,
    this.isActive = true,
  });
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
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _addMedicine(Medicine med) {
    setState(() => medicines.add(med));
    _scheduleNotifications(med);
  }

  void _scheduleNotifications(Medicine med) async {
    if (!med.isActive) return;

    for (int i = 0; i < med.timesPerDay; i++) {
      final now = DateTime.now();
      final scheduledDate = now.add(Duration(minutes: 1 + i * 2)); // demo timing

      AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'medicine_channel',
        'Medicine Reminders',
        channelDescription: 'Remind to take medicine',
        importance: Importance.max,
        priority: Priority.high,
        playSound: med.alarmSound,
        enableVibration: true,
      );

      NotificationDetails details = NotificationDetails(android: androidDetails);

      await flutterLocalNotificationsPlugin.zonedSchedule(
        i,
        '🩺 Time to take medicine!',
        '\( {med.name} - Dose \){i + 1}/${med.timesPerDay}',
        tz.TZDateTime.from(scheduledDate, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medicine Reminder', style: TextStyle(fontSize: 20)),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: medicines.isEmpty
          ? const Center(
              child: Text(
                'No medicines added yet',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            )
          : ListView.builder(
              itemCount: medicines.length,
              itemBuilder: (context, index) {
                final med = medicines[index];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D1D1D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    title: Text(
                      '\( {med.timesPerDay == 1 ? "Once" : " \){med.timesPerDay} times"} daily',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w300,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      '\( {med.name} • \){med.totalTablets} tablets left',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    trailing: Switch(
                      value: med.isActive,
                      activeColor: Colors.blue,
                      onChanged: (val) {
                        setState(() => med.isActive = val);
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0A84FF),
        child: const Icon(Icons.add, size: 32),
        onPressed: () => Navigator.push(
          context,
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
  int _totalTablets = 10;
  bool _notificationOnly = true;
  bool _alarmSound = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: TextButton(
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Add Medicine'),
        actions: [
          TextButton(
            onPressed: _nameController.text.isEmpty
                ? null
                : () {
                    final med = Medicine(
                      name: _nameController.text,
                      timesPerDay: _timesPerDay,
                      totalTablets: _totalTablets,
                      notificationOnly: _notificationOnly,
                      alarmSound: _alarmSound,
                    );
                    widget.onSave(med);
                    Navigator.pop(context);
                  },
            child: const Text('Save', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Medicine Name
          TextField(
            controller: _nameController,
            style: const TextStyle(fontSize: 20, color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Medicine name (e.g., Paracetamol)',
              hintStyle: TextStyle(color: Colors.grey),
              border: InputBorder.none,
            ),
          ),
          const Divider(color: Colors.grey),

          const SizedBox(height: 30),

          // Times per day slider
          const Text('How many times a day?',
              style: TextStyle(fontSize: 18, color: Colors.white70)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (i) {
              final times = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _timesPerDay = times),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _timesPerDay == times
                        ? Colors.blue
                        : const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$times×',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color:
                          _timesPerDay == times ? Colors.white : Colors.grey,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              '$_timesPerDay kali sehari',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w300),
            ),
          ),

          const SizedBox(height: 40),

          // Total tablets
          const Text('Total tablets / strips',
              style: TextStyle(fontSize: 18, color: Colors.white70)),
          const SizedBox(height: 10),
          TextField(
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 24, color: Colors.white),
            decoration: InputDecoration(
              hintText: '$_totalTablets',
              hintStyle: const TextStyle(color: Colors.grey),
              border: InputBorder.none,
            ),
            onChanged: (v) {
              _totalTablets = int.tryParse(v) ?? 10;
            },
          ),
          const Divider(color: Colors.grey),

          const SizedBox(height: 30),

          // Notification type
          ListTile(
            title: const Text('Notification only',
                style: TextStyle(color: Colors.white)),
            trailing: Switch(
              value: _notificationOnly,
              activeColor: Colors.blue,
              onChanged: (val) {
                setState(() {
                  _notificationOnly = val;
                  if (val) _alarmSound = false;
                });
              },
            ),
          ),
          ListTile(
            title: const Text('Alarm sound',
                style: TextStyle(color: Colors.white)),
            trailing: Switch(
              value: _alarmSound,
              activeColor: Colors.blue,
              onChanged: (val) {
                setState(() {
                  _alarmSound = val;
                  if (val) _notificationOnly = false;
                });
              },
            ),
          ),
          ListTile(
            title: const Text('Both notification + alarm',
                style: TextStyle(color: Colors.white70)),
            trailing: Switch(
              value: !_notificationOnly && !_alarmSound,
              activeColor: Colors.blue,
              onChanged: (val) {
                if (val) {
                  setState(() {
                    _notificationOnly = false;
                    _alarmSound = false;
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}