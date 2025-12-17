// UI mới nhất
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'mqtt_service.dart';

void main() => runApp(const SmartFanApp());

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

  String mqttStatus = "Connecting...";
  Color mqttColor = Colors.yellow;

  bool fanOn = false;
  int fanSpeed = 0;
  bool oscillation = false;

  String temperature = "--";

  Timer? timer;
  int remainingSeconds = 0;
  final TextEditingController hourController = TextEditingController();
  final TextEditingController minuteController = TextEditingController();
  final TextEditingController secondController = TextEditingController();

  @override
  void initState() {
    super.initState();
    mqttService = MQTTClientWrapper(onMessage: _handleMqttMessage);
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

  Future<void> connectMQTT() async {
    setState(() {
      mqttStatus = "Connecting...";
      mqttColor = Colors.yellow;
    });

    await mqttService.prepareMqttClient();

    setState(() {
      if (mqttService.connectionState == MqttCurrentConnectionState.connected) {
        mqttStatus = "Connected";
        mqttColor = Colors.greenAccent;
      } else {
        mqttStatus = "Disconnected";
        mqttColor = Colors.redAccent;
      }
    });
  }

  void _handleMqttMessage(String topic, String payload) {
    setState(() {
      switch (topic) {
        case MQTTClientWrapper.topicRoomTemp:
          temperature = payload;
          break;

        case MQTTClientWrapper.topicFanState:
          fanOn = (payload == "ON" || payload == "1");
          if (!fanOn) _resetFanLocalState();
          break;

        case MQTTClientWrapper.topicFanSpeed:
          final sp = int.tryParse(payload) ?? 0;
          fanSpeed = sp;
          if (sp > 0) fanOn = true;
          break;

        case MQTTClientWrapper.topicFanOsc:
          oscillation = (payload == "ON" || payload == "1");
          break;
      }
    });
  }

  void _sendFanState() => mqttService.publishFanState(fanOn ? "ON" : "OFF");
  void _sendFanSpeed() => mqttService.publishFanSpeed(fanSpeed.toString());
  void _sendOscState() => mqttService.publishFanOsc(oscillation ? "ON" : "OFF");

  void _resetFanLocalState() {
    fanSpeed = 0;
    oscillation = false;
    remainingSeconds = 0;
    timer?.cancel();
  }

  void togglePower() {
    setState(() {
      fanOn = !fanOn;
      if (!fanOn) _resetFanLocalState();
    });

    _sendFanState();

    if (!fanOn) {
      mqttService.publishFanSpeed("0");
      mqttService.publishFanOsc("OFF");
    }
  }

  void setFanSpeed(int level) {
    if (!fanOn) return;

    setState(() {
      fanSpeed = level;
      if (level == 0) oscillation = false;
    });

    _sendFanSpeed();
    if (level == 0) _sendOscState();
  }

  void toggleOscillation() {
    if (!fanOn) return;
    setState(() => oscillation = !oscillation);
    _sendOscState();
  }

  void startTimer() {
    if (!fanOn) return;

    int hours = int.tryParse(hourController.text) ?? 0;
    int minutes = int.tryParse(minuteController.text) ?? 0;
    int seconds = int.tryParse(secondController.text) ?? 0;

    final totalSeconds = hours * 3600 + minutes * 60 + seconds;
    if (totalSeconds <= 0) return;
    setState(() => remainingSeconds = totalSeconds );
    // Đẩy timer giây lên MQTT
    mqttService.publishFanTimer(totalSeconds.toString());

    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => remainingSeconds--);
      if (remainingSeconds <= 0) {
        t.cancel();
        _turnOffCompletely(); // tắt quạt + pub OFF
      }
    });
  }

  void stopTimer() {
    timer?.cancel();
    setState(() => remainingSeconds = 0);
    // Nhấn Stop thì gửi 0 = Không hẹn giờ
    mqttService.publishFanTimer("0");
  }

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
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // nền xanh như ảnh neon
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  children: [
                    _header(),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(child: _temperatureCard()),
                        const SizedBox(width: 12),
                        Expanded(child: _oscillationCard()), // KHÔNG neon
                      ],
                    ),

                    const SizedBox(height: 14),

                    _disabledWrap(enabled: fanOn, child: _speedCard()),

                    const SizedBox(height: 14),

                    _disabledWrap(enabled: fanOn, child: _timerCard()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================= HEADER =================
  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.3),
        color: Colors.white.withOpacity(0.08),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Smart fan controller",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: mqttColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      mqttStatus,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          CupertinoTheme(
            data: CupertinoThemeData(
              // OFF rõ hơn: trackColor sáng hơn (xám nhạt)
              primaryColor: Colors.greenAccent,
            ),
            child: Transform.scale(
              scale: 1.1, // to hơn chút cho dễ nhìn
              child: CupertinoSwitch(
                value: fanOn,
                onChanged: (_) => togglePower(),
                activeColor: Colors.greenAccent,
                trackColor: Colors.white.withOpacity(0.35), // OFF rõ hơn
                thumbColor: Colors.white, // nút tròn trắng rõ
              ),
            ),
          ),

        ],
      ),
    );
  }

  // ================= Temperature =================
  Widget _temperatureCard() {
    return _panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _titleRow(icon: Icons.home, title: "Temperature"),
          const SizedBox(height: 10),
          Text(
            "$temperature °C",
            style: const TextStyle(
              fontSize: 28,
              color: Colors.yellowAccent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ================= Oscillation (KHÔNG neon) =================
  Widget _oscillationCard() {
    return _disabledWrap(
      enabled: fanOn,
      child: _panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _titleRow(icon: Icons.sync, title: "Oscillation"),
            const SizedBox(height: 8),
            CupertinoTheme(
              data: CupertinoThemeData(
                // màu chủ đạo khi ON
                primaryColor: Colors.greenAccent,
              ),
              child: Opacity(
                // khi tắt nguồn thì mờ, khi bật nguồn thì rõ
                opacity: fanOn ? 1.0 : 0.4,
                child: Transform.scale(
                  scale: 1.05, // to hơn chút cho dễ nhìn trên desktop
                  child: CupertinoSwitch(
                    value: oscillation,
                    onChanged: fanOn ? (_) => toggleOscillation() : null,

                    // ===== FIX HIỂN THỊ WINDOWS =====
                    activeColor: Colors.greenAccent,                 // ON
                    trackColor: Colors.white.withOpacity(0.35),     // OFF vẫn rõ
                    thumbColor: Colors.white,                       // nút tròn rõ
                  ),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  // ================= Speed (NEON chỉ nút active) =================
  Widget _speedCard() {
    return _panel(
      child: Column(
        children: [
          _titleRow(icon: Icons.air, title: "Speed"),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _speedButton("Low", 1),
              _speedButton("Med", 2),
              _speedButton("High", 3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _speedButton(String text, int level) {
    final bool active = fanOn && (fanSpeed == level);

    return PressableScale(
      enabled: fanOn,
      onTap: () => setFanSpeed(level),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? Colors.cyanAccent : Colors.white,
            width: 1.6,
          ),
          color: active ? Colors.cyanAccent.withOpacity(0.12) : Colors.transparent,
          boxShadow: active
              ? [
            BoxShadow(
              color: Colors.cyanAccent.withOpacity(0.85),
              blurRadius: 22,
              spreadRadius: 1.5,
            )
          ]
              : [],
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: active ? Colors.cyanAccent : Colors.white,
          ),
        ),
      ),
    );
  }

  // ================= Timer =================
  Widget _timerCard() {
    return _panel(
      child: Column(
        children: [
          _titleRow(icon: Icons.timer, title: "Timer"),
          const SizedBox(height: 12),
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
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PressableScale(
                enabled: fanOn,
                onTap: startTimer,
                child: _actionButton("Start", danger: false),
              ),
              const SizedBox(width: 14),
              PressableScale(
                enabled: fanOn,
                onTap: stopTimer,
                child: _actionButton("Stop", danger: true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            remainingSeconds > 0 ? "Remaining: ${formatHHMMSS(remainingSeconds)}" : "No timer",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ================= UI Helpers =================
  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 1.3),
        color: Colors.white.withOpacity(0.08),
      ),
      child: child,
    );
  }

  Widget _titleRow({required IconData icon, required String title}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: Colors.white),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _disabledWrap({required bool enabled, required Widget child}) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: IgnorePointer(
        ignoring: !enabled,
        child: child,
      ),
    );
  }

  Widget _actionButton(String text, {required bool danger}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: danger ? Colors.red : Colors.white,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: danger ? Colors.white : Colors.black,
        ),
      ),
    );
  }

  Widget _timeField(TextEditingController controller, String label) {
    return SizedBox(
      width: 92,
      child: TextField(
        enabled: fanOn,
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: Colors.white.withOpacity(0.08),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white, width: 1.1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.6),
          ),
        ),
      ),
    );
  }
}

/// Press effect: scale + “nháy” 80ms (giống app thật)
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final Duration duration;

  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.enabled = true,
    this.duration = const Duration(milliseconds: 80),
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _setDown(bool v) {
    if (!widget.enabled) return;
    if (_down == v) return;
    setState(() => _down = v);
  }

  Future<void> _tap() async {
    if (!widget.enabled || widget.onTap == null) return;
    _setDown(true);
    await Future.delayed(widget.duration);
    _setDown(false);
    widget.onTap!.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _down ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 80),
      child: AnimatedOpacity(
        opacity: _down ? 0.85 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: GestureDetector(
          onTapDown: (_) => _setDown(true),
          onTapCancel: () => _setDown(false),
          onTapUp: (_) => _setDown(false),
          onTap: _tap,
          child: widget.child,
        ),
      ),
    );
  }
}
