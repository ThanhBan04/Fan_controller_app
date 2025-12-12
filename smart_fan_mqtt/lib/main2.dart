// UI cũ
// Bản hoàn chỉnh có cả publish từ app lên cloud và cập nhật từ cloud xuống app.
// Gồm các chức năng: Bật/Tắt nguồn, 3 chế độ speed,đứng/quay, hẹn giờ, hiển thị nhiệt độ.
// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'mqtt_service.dart';
import 'package:flutter/cupertino.dart';

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
  bool fanOn = false;      // chỉ bật / tắt nguồn
  int fanSpeed = 0;        // 0 = off, 1 = low, 2 = med, 3 = high
  bool oscillation = false; // 0 = off, 1 = on

  // Temperature
  String temperature = "--";

  // Timer
  Timer? timer;
  int remainingSeconds = 0;
  final TextEditingController hourController = TextEditingController();
  final TextEditingController minuteController = TextEditingController();
  final TextEditingController secondController = TextEditingController();

  @override
  void initState() {
    super.initState();

    mqttService = MQTTClientWrapper(
      onMessage: _handleMqttMessage,
    );

    connectMQTT();
  }

  @override
  void dispose() {
    timer?.cancel();
    hourController.dispose();
    minuteController.dispose();
    secondController.dispose();
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

  // ================== HANDLE MQTT FROM CLOUD ==================
  void _handleMqttMessage(String topic, String payload) {
    setState(() {
      switch (topic) {
        case MQTTClientWrapper.topicRoomTemp:
          temperature = payload;
          break;

        case MQTTClientWrapper.topicFanState:
        // Nguồn từ Cloud: ON/OFF hoặc 1/0
          fanOn = (payload == "ON" || payload == "1");
          if (!fanOn) {
            // nếu tắt nguồn từ Cloud thì app cũng tắt tất cả
            _resetFanLocalState();
          }
          break;

        case MQTTClientWrapper.topicFanSpeed:
          final sp = int.tryParse(payload) ?? 0;
          fanSpeed = sp;
          // tuỳ bạn: nếu Cloud gửi speed > 0 thì xem như bật nguồn
          if (sp > 0) fanOn = true;
          break;

        case MQTTClientWrapper.topicFanOsc:
          oscillation = (payload == "ON" || payload == "1");
          break;
      }
    });
  }

  // ================= MQTT SEND =================
  void _sendFanState() {
    mqttService.publishFanState(fanOn ? "ON" : "OFF");
  }

  void _sendFanSpeed() {
    mqttService.publishFanSpeed(fanSpeed.toString());
  }

  void _sendOscState() {
    mqttService.publishFanOsc(oscillation ? "ON" : "OFF");
  }

  // ================= FAN POWER CONTROL =================

  /// Hàm reset state local khi tắt nguồn
  void _resetFanLocalState() {
    fanSpeed = 0;
    oscillation = false;
    remainingSeconds = 0;
    timer?.cancel();
  }

  /// Bật/tắt nguồn từ UI
  void togglePower() {
    setState(() {
      fanOn = !fanOn;
      if (!fanOn) {
        _resetFanLocalState();
      }
    });

    // Gửi MQTT trạng thái nguồn
    _sendFanState();

    // Nếu tắt nguồn thì gửi luôn speed=0 và osc=OFF
    if (!fanOn) {
      mqttService.publishFanSpeed("0");
      mqttService.publishFanOsc("OFF");
    }
  }

  // ================= FAN SPEED / OSC CONTROL =================

  /// Chỉ đổi speed khi nguồn đang ON
  void setFanSpeed(int level) {
    if (!fanOn) return;

    setState(() {
      fanSpeed = level;

      if (level == 0) {
        oscillation = false;
      }
    });

    _sendFanSpeed();

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
  void startTimer() {
    if (!fanOn) return;

    int hours = int.tryParse(hourController.text) ?? 0;
    int minutes = int.tryParse(minuteController.text) ?? 0;
    int seconds = int.tryParse(secondController.text) ?? 0;

    remainingSeconds = hours * 3600 + minutes * 60 + seconds;

    if (remainingSeconds <= 0) return;

    timer?.cancel();

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        remainingSeconds--;
      });

      if (remainingSeconds <= 0) {
        t.cancel();
        _turnOffCompletely(); // hết giờ thì tắt nguồn luôn
      }
    });
  }

  void stopTimer() {
    timer?.cancel();
    setState(() => remainingSeconds = 0);
  }

  /// Tắt nguồn hoàn toàn (cho timer hoặc case khác dùng)
  void _turnOffCompletely() {
    setState(() {
      fanOn = false;
      _resetFanLocalState();
    });

    _sendFanState();
    mqttService.publishFanSpeed("0");
    mqttService.publishFanOsc("OFF");
  }

  String formatHHMMSS(int sec) {
    int h = sec ~/ 3600;
    int m = (sec % 3600) ~/ 60;
    int s = sec % 60;

    String hh = h.toString().padLeft(2, '0');
    String mm = m.toString().padLeft(2, '0');
    String ss = s.toString().padLeft(2, '0');

    return "$hh:$mm:$ss";
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
                    GlassCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 6),
                          const Text(
                            "Temperature",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: temperature,
                                  style: const TextStyle(
                                    color: Colors.yellow,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const TextSpan(
                                  text: " °C",
                                  style: TextStyle(
                                    color: Colors.yellow,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ],
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

                    // Power button (chỉ bật/tắt nguồn)
                    GestureDetector(
                      onTap: togglePower,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: fanOn
                              ? Colors.greenAccent
                              : Colors.white24,
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

    return Opacity(
      opacity: fanOn ? 1.0 : 0.4,         //  nguồn tắt thì mờ giống LOW/MED/HIGH
      child: GestureDetector(
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

  // =============== Timer UI (Hẹn giờ) ===============
  Widget timerSection() {
    return Column(
      children: [
        const Text(
          "Timer",
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        // --- Inputs: HH MM SS ---
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _timeField(hourController, "Hours"),
            const SizedBox(width: 10),
            _timeField(minuteController, "Minutes"),
            const SizedBox(width: 10),
            _timeField(secondController, "Seconds"),
          ],
        ),

        const SizedBox(height: 16),

        // --- Buttons ---
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: fanOn ? startTimer : null,
              child: const Text("Start"),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: fanOn ? stopTimer : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text("Stop"),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // --- Remaining time ---
        Text(
          remainingSeconds > 0
              ? "Remaining: ${formatHHMMSS(remainingSeconds)}"
              : "No timer",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  // Ô nhập thời gian cho Hours/Minutes/Seconds
  Widget _timeField(TextEditingController controller, String label) {
    return SizedBox(
      width: 80,
      child: TextField(
        enabled: fanOn,
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white38),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.cyanAccent),
          ),
        ),
      ),
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

