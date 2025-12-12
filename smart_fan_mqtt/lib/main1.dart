// Code chạy oke, copy lại cho yên tâm ^^
// Code chỉ mới có publish topic lên cloud
// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'mqtt_service.dart';

void main() {
  runApp(const SmartFanApp());
}

class SmartFanApp extends StatelessWidget {
  const SmartFanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Smart Fan",
      theme: ThemeData(useMaterial3: true),
      home: const FanHomePage(),
    );
  }
}

class FanHomePage extends StatefulWidget {
  const FanHomePage({super.key});

  @override
  State<FanHomePage> createState() => _FanHomePageState();
}

class _FanHomePageState extends State<FanHomePage> {
  late MQTTClientWrapper mqttService;

  // MQTT status
  String mqttStatus = "Connecting...";
  Color mqttColor = Colors.yellow;

  // Fan state
  bool fanOn = false;
  int fanSpeed = 0; // 0 = off, 1 = low, 2 = med, 3 = high
  bool oscillation = false;

  // Temperature
  String temperature = "-- °C";

  // Timer
  Timer? timer;
  int remainingSeconds = 0;
  final TextEditingController minuteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    mqttService = MQTTClientWrapper();
    connectMQTT();
  }

  @override
  void dispose() {
    timer?.cancel();
    minuteController.dispose();
    super.dispose();
  }

  // ================= MQTT CONNECT =================
  Future<void> connectMQTT() async {
    setState(() {
      mqttStatus = "Connecting...";
      mqttColor = Colors.yellow;
    });

    await mqttService.prepareMqttClient();

    setState(() {
      if (mqttService.connectionState ==
          MqttCurrentConnectionState.connected) {
        mqttStatus = "Connected";
        mqttColor = Colors.greenAccent;
      } else {
        mqttStatus = "Disconnected";
        mqttColor = Colors.redAccent;
      }
    });
  }

  // ================= MQTT SEND =================
  // Lưu ý: mqtt_service.dart định nghĩa:
  //  - publishFanState(String state)  // "ON" hoặc "OFF"
  //  - publishFanSpeed(String speed)  // "0".."3"
  //  - publishFanOsc(String oscState) // "ON" hoặc "OFF"

  void _sendFanState() {
    mqttService.publishFanState(fanOn ? "ON" : "OFF");
  }

  void _sendFanSpeed() {
    mqttService.publishFanSpeed(fanSpeed.toString());
  }

  void _sendOscState() {
    mqttService.publishFanOsc(oscillation ? "ON" : "OFF");
  }

  // ================= FAN CONTROL =================
  void setFanSpeed(int level) {
    // Không cho nhảy từ OFF -> MED/HIGH trực tiếp
    if (!fanOn && level != 1 && level != 0) return;

    setState(() {
      fanSpeed = level;
      fanOn = level != 0;

      if (level == 0) {
        oscillation = false;
      }
    });

    _sendFanSpeed();
    _sendFanState();

    if (level == 0) {
      _sendOscState();
    }
  }

  void toggleOscillation() {
    if (!fanOn) return;

    setState(() {
      oscillation = !oscillation;
    });

    _sendOscState();
  }

  // ================= TIMER =================
  void startTimer(int seconds) {
    if (!fanOn) return;

    remainingSeconds = seconds;
    timer?.cancel();

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        remainingSeconds--;
      });

      if (remainingSeconds <= 0) {
        t.cancel();
        setFanSpeed(0); // trong này đã tắt osc và publish luôn
      }
    });
  }

  void stopTimer() {
    timer?.cancel();
    setState(() => remainingSeconds = 0);
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff1e3c72), Color(0xff2a5298)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Column(
                  children: [
                    const Text(
                      "Smart Fan Controller",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // MQTT Status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: mqttColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          mqttStatus,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 25),

                    // Temperature card
                    const GlassCard(
                      child: Column(
                        children: [
                          Icon(
                            Icons.thermostat,
                            color: Colors.white,
                            size: 40,
                          ),
                          SizedBox(height: 6),
                          Text(
                            "Nhiệt độ phòng",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
                    Text(
                      temperature,
                      style: const TextStyle(
                        color: Colors.yellow,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 25),

                    // Oscillation
                    oscButton(),

                    const SizedBox(height: 30),

                    // Speed buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        neonButton("LOW", 1),
                        neonButton("MED", 2),
                        neonButton("HIGH", 3),
                      ],
                    ),

                    const SizedBox(height: 30),

                    // Power button
                    GestureDetector(
                      onTap: () => setFanSpeed(fanOn ? 0 : 1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: fanOn ? Colors.greenAccent : Colors.white24,
                        ),
                        child: Icon(
                          fanOn
                              ? Icons.power_settings_new
                              : Icons.power_off,
                          size: 50,
                          color: fanOn ? Colors.black : Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Timer
                    timerSection(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =============== Oscillation Button ===============
  Widget oscButton() {
    final active = oscillation;

    return GestureDetector(
      onTap: fanOn ? toggleOscillation : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? Colors.cyanAccent : Colors.white60,
            width: 2,
          ),
          boxShadow: active
              ? [
            BoxShadow(
              color: Colors.cyanAccent.withOpacity(0.7),
              blurRadius: 22,
            )
          ]
              : [],
        ),
        child: Text(
          active ? "OSCILLATION ON" : "OSCILLATION OFF",
          style: TextStyle(
            color: active ? Colors.cyanAccent : Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // =============== Speed Button ===============
  Widget neonButton(String text, int level) {
    final active = fanSpeed == level;

    return Opacity(
      opacity: fanOn ? 1 : 0.4,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? Colors.cyanAccent : Colors.white60,
            width: 2,
          ),
          boxShadow: active
              ? [
            BoxShadow(
              color: Colors.cyanAccent.withOpacity(0.6),
              blurRadius: 20,
            )
          ]
              : [],
        ),
        child: InkWell(
          onTap: fanOn ? () => setFanSpeed(level) : null,
          child: Text(
            text,
            style: TextStyle(
              color: active ? Colors.cyanAccent : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // =============== Timer UI ===============
  Widget timerSection() {
    return Column(
      children: [
        const Text(
          "Hẹn giờ",
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 140,
              child: TextField(
                enabled: fanOn,
                controller: minuteController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Số phút",
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white38),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.cyanAccent),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: fanOn
                  ? () {
                int minutes =
                    int.tryParse(minuteController.text) ?? 0;
                if (minutes > 0) {
                  startTimer(minutes * 60);
                }
              }
                  : null,
              child: const Text("Bắt đầu"),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: fanOn ? stopTimer : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text("Dừng"),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          remainingSeconds > 0
              ? "Còn lại: $remainingSeconds giây"
              : "Không có hẹn giờ",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

// Glass card UI
class GlassCard extends StatelessWidget {
  final Widget child;
  const GlassCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withOpacity(0.1),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 18,
          ),
        ],
      ),
      child: child,
    );
  }
}
