import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    ChangeNotifierProvider(
      create: (_) => MqttFirestoreState(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "ScobiGO Dashboard",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ScobiGO IoT Dashboard")),
      body: Consumer<MqttFirestoreState>(
        builder: (context, s, _) {
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // ====================== STATUS MODE ======================
                  Card(
                    color: s.mode == "auto" ? Colors.green[300] : Colors.orange[300],
                    child: ListTile(
                      title: const Text("MODE"),
                      trailing: Text(s.mode.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ====================== GAUGE GAS ======================
                  SfRadialGauge(
                    enableLoadingAnimation: true,
                    title: const GaugeTitle(
                      text: 'Gas Level (MQ-7)',
                      textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    axes: <RadialAxis>[
                      RadialAxis(
                        minimum: 0,
                        maximum: 4095,
                        ranges: <GaugeRange>[
                          GaugeRange(startValue: 0, endValue: 1500, color: Colors.green),
                          GaugeRange(startValue: 1500, endValue: 2500, color: Colors.orange),
                          GaugeRange(startValue: 2500, endValue: 4095, color: Colors.red),
                        ],
                        pointers: <GaugePointer>[
                          NeedlePointer(value: s.gas.toDouble()),
                        ],
                        annotations: <GaugeAnnotation>[
                          GaugeAnnotation(
                            widget: Text('${s.gas}'),
                            angle: 90,
                            positionFactor: 0.7,
                          )
                        ],
                      )
                    ],
                  ),

                  const SizedBox(height: 15),

                  // ====================== RADAR ======================
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Colors.black, Colors.blueGrey],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    height: 200,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: RadarPainter(distance: s.distance),
                      child: Center(
                        child: Text(
                          "${s.distance} cm",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ====================== MODE BUTTON ======================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          onPressed: () => s.publishControl('mode', 'auto'),
                          child: const Text("AUTO")),
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                          onPressed: () => s.publishControl('mode', 'manual'),
                          child: const Text("MANUAL")),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ====================== CONTROL SERVO ======================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      ElevatedButton(
                          onPressed: () => s.publishControl('servo', '{"angle":0}'),
                          child: const Text("Servo 0")),
                      ElevatedButton(
                          onPressed: () => s.publishControl('servo', '{"angle":90}'),
                          child: const Text("Servo 90")),
                      ElevatedButton(
                          onPressed: () => s.publishControl('servo', '{"angle":180}'),
                          child: const Text("Servo 180")),
                    ],
                  ),

                  const SizedBox(height: 15),

                  // ====================== CONTROL LED ======================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      ElevatedButton(
                          onPressed: () => s.publishControl('led', '1'),
                          child: const Text("LED ON")),
                      ElevatedButton(
                          onPressed: () => s.publishControl('led', '0'),
                          child: const Text("LED OFF")),
                    ],
                  ),

                  const SizedBox(height: 20),

                  const Text("History Firestore (latest 10)", style: TextStyle(fontSize: 16)),

                  // ====================== Firebase History ======================
                  SizedBox(
                    height: 200,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('sensor_data')
                          .orderBy('timestamp', descending: true)
                          .limit(10)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final docs = snapshot.data!.docs;
                        return ListView(
                          children: docs.map((d) {
                            final data = d.data() as Map<String, dynamic>;
                            return ListTile(
                              title: Text("Gas: ${data['gas']} - PIR: ${data['pir']}"),
                              subtitle: Text("Dist: ${data['distance_cm']} cm"),
                              trailing: Text(data['timestamp']?.toString() ?? ''),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =======================================================================================
// MQTT + FIRESTORE LOGIC
// =======================================================================================
class MqttFirestoreState extends ChangeNotifier {
  final String broker = 'broker.hivemq.com';
  final int port = 1883;
  late MqttServerClient client;
  bool connected = false;
  String deviceId = "esp32-01"; // <= GANTI SESUAI ESP32 MU

  int gas = 0;
  int pir = 0;
  int distance = 0;
  String mode = "auto";

  MqttFirestoreState() {
    _setupClient();
    _connect();

    FirebaseFirestore.instance
        .collection('sensor_data')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data();
        gas = (d['gas'] ?? gas).toInt();
        pir = (d['pir'] ?? pir).toInt();
        distance = (d['distance_cm'] ?? distance).toInt();
        notifyListeners();
      }
    });
  }

  void _setupClient() {
    client = MqttServerClient(broker, "flutter_${DateTime.now().millisecondsSinceEpoch}");
    client.port = port;
    client.keepAlivePeriod = 20;
    client.onConnected = () {
      connected = true;
      notifyListeners();
    };
    client.onDisconnected = () {
      connected = false;
      notifyListeners();
    };
    client.onSubscribed = (topic) {};
  }

  Future<void> _connect() async {
    try {
      await client.connect();
    } catch (e) {
      client.disconnect();
      return;
    }
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      client.subscribe("scobigo/sensor/$deviceId", MqttQos.atMostOnce);
      client.subscribe("scobigo/control/$deviceId/mode", MqttQos.atMostOnce);
      client.updates?.listen(_onMessage);
    }
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>>? events) {
    final msg = events![0].payload as MqttPublishMessage;
    final payload = MqttPublishPayload.bytesToStringAsString(msg.payload.message);

    if (events[0].topic!.endsWith("/mode")) {
      mode = payload;
      notifyListeners();
      return;
    }

    try {
      final data = jsonDecode(payload);
      gas = (data['gas'] ?? gas).toInt();
      pir = (data['pir'] ?? pir).toInt();
      distance = (data['jarak'] ?? distance).toInt();
      notifyListeners();
    } catch (_) {}
  }

  void publishControl(String sub, dynamic value) {
    if (!connected) return;
    final topic = "scobigo/control/$deviceId/$sub";
    final builder = MqttClientPayloadBuilder();
    builder.addUTF8String(value.toString());
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }
}

// =======================================================================================
// RADAR PAINTER UI
// =======================================================================================
class RadarPainter extends CustomPainter {
  final int distance;
  RadarPainter({required this.distance});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    double radius = size.width * 0.45;
    Offset center = Offset(size.width / 2, size.height / 2);

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * (i / 3), paint);
    }

    double sweepAngle = (distance <= 20) ? 3.14 / 3 : 3.14 / 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -sweepAngle,
      sweepAngle * 2,
      false,
      paint..color = (distance <= 20) ? Colors.red : Colors.lightGreenAccent,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
