import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

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
  late MqttBrowserClient client;

  // Status
  String mqttStatus = "Connecting...";
  Color mqttColor = Colors.yellow;

  // Fan
  bool fanOn = false;
  int fanSpeed = 0;
  bool oscillation = false;

  // Temp
  String temperature = "-- °C";

  // Timer
  Timer? timer;
  int remainingSeconds = 0;
  final TextEditingController minuteController = TextEditingController();

  // HiveMQ Cloud
  final String host =
      "099f0f049a6d49bca9614e32470c2276.s1.eu.hivemq.cloud";
  final String username = "Thanh_Ban_04";
  final String password = "Tb123456";

  @override
  void initState() {
    super.initState();
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
    // Chỉ để host, KHÔNG kèm :port/mqtt ở đây
    const String host = '099f0f049a6d49bca9614e32470c2276.s1.eu.hivemq.cloud';

    client = MqttBrowserClient('wss://$host/mqtt', 'flutter_fan_client');

    // Cấu hình WebSocket + MQTT
    client.port = 8884;                      // WebSocket TLS port
    // Ép dùng MQTT 3.1.1
    client.setProtocolV311();
    client.websocketProtocols = MqttClientConstants.protocolsSingleDefault; // 'mqtt'
    client.logging(on: true);
    client.keepAlivePeriod = 20;

    setState(() {
      mqttStatus = "Connecting...";
      mqttColor = Colors.yellow;
    });

    final connMess = MqttConnectMessage()
        .withClientIdentifier('flutter_fan_client')
        .authenticateAs(username, password)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    client.connectionMessage = connMess;

    try {
      await client.connect();
      setState(() {
        mqttStatus = "Connected";
        mqttColor = Colors.greenAccent;
      });
    } catch (e) {
      print('MQTT CONNECT EXCEPTION: $e');
      print('MQTT CONNECTION STATUS: ${client.connectionStatus}');
      client.disconnect();
      setState(() {
        mqttStatus = "Disconnected";
        mqttColor = Colors.redAccent;
      });
      Future.delayed(const Duration(seconds: 2), connectMQTT);
      return;
    }

    client.onDisconnected = () {
      setState(() {
        mqttStatus = "Disconnected";
        mqttColor = Colors.redAccent;
      });
      Future.delayed(const Duration(seconds: 2), connectMQTT);
    };

    subscribeTopics();
    // URL WebSocket đầy đủ cho HiveMQ Cloud
    // final url =
    //     'wss://$host/mqtt';
    // client = MqttBrowserClient(url, 'flutter_fan_client');
    // client.port = 8884; // ÉP PORT 8884 CHO WEB SOCKET
    // client.logging(on: true);
    // client.keepAlivePeriod = 20;
    // setState(() {
    //   mqttStatus = "Connecting...";
    //   mqttColor = Colors.yellow;
    // });
    //
    // final connMess = MqttConnectMessage()
    //     .withClientIdentifier('flutter_fan_client')
    //     .authenticateAs(username, password)
    //     .startClean()
    //     .withWillQos(MqttQos.atLeastOnce);
    //
    // client.connectionMessage = connMess;
    //
    // try {
    //   await client.connect();
    //   setState(() {
    //     mqttStatus = "Connected";
    //     mqttColor = Colors.greenAccent;
    //   });
    // } catch (e) {
    //   print('MQTT CONNECT EXCEPTION: $e');
    //   print('MQTT CONNECTION STATUS: ${client.connectionStatus}');
    //   client.disconnect();
    //   setState(() {
    //     mqttStatus = "Disconnected";
    //     mqttColor = Colors.redAccent;
    //   });
    //   Future.delayed(const Duration(seconds: 2), connectMQTT);
    //   return;
    // }
    //
    // client.onDisconnected = () {
    //   setState(() {
    //     mqttStatus = "Disconnected";
    //     mqttColor = Colors.redAccent;
    //   });
    //   Future.delayed(const Duration(seconds: 2), connectMQTT);
    // };
    //
    // subscribeTopics();

    client.updates!.listen((events) {
      final msg = events[0].payload as MqttPublishMessage;
      final payload =
      MqttPublishPayload.bytesToStringAsString(msg.payload.message);

      switch (events[0].topic) {
        case "iot/room/temp":
          setState(() => temperature = "$payload °C");
          break;
        case "iot/fan/state":
          setState(() {
            fanOn = payload == "1";
            if (!fanOn) {
              fanSpeed = 0;
              oscillation = false;
            }
          });
          break;
        case "iot/fan/speed":
          int sp = int.tryParse(payload) ?? 0;
          setState(() {
            fanSpeed = sp;
            fanOn = sp != 0;
          });
          break;
        case "iot/fan/osc":
          setState(() => oscillation = payload == "1");
          break;
      }
    });
  }
  void subscribeTopics() {
    client.subscribe("iot/room/temp", MqttQos.atMostOnce);
    client.subscribe("iot/fan/state", MqttQos.atMostOnce);
    client.subscribe("iot/fan/speed", MqttQos.atMostOnce);
    client.subscribe("iot/fan/osc", MqttQos.atMostOnce);
  }

  // ================= MQTT SEND =================
  void publish(String topic, String msg) {
    if (client.connectionStatus?.state != MqttConnectionState.connected) return;

    final builder = MqttClientPayloadBuilder();
    builder.addString(msg);
    client.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
  }

  // ================= FAN CONTROL =================
  void setFanSpeed(int level) {
    if (!fanOn && level != 1) return;

    setState(() {
      fanSpeed = level;
      fanOn = level != 0;

      // FIX: When turning OFF → stop oscillation
      if (level == 0) {
        oscillation = false;
      }
    });

    publish("iot/fan/speed", level.toString());
    publish("iot/fan/state", fanOn ? "1" : "0");

    if (level == 0) {
      publish("iot/fan/osc", "0"); // FIX
    }
  }

  void toggleOscillation() {
    if (!fanOn) return;

    setState(() => oscillation = !oscillation);
    publish("iot/fan/osc", oscillation ? "1" : "0");
  }

  // ================= TIMER =================
  void startTimer(int seconds) {
    if (!fanOn) return;

    remainingSeconds = seconds;
    timer?.cancel();

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => remainingSeconds--);

      if (remainingSeconds <= 0) {
        t.cancel();
        setFanSpeed(0);
        oscillation = false;
        publish("iot/fan/osc", "0");
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
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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

                    // Temperature
                    GlassCard(
                      child: Column(
                        children: [
                          const Icon(Icons.thermostat,
                              color: Colors.white, size: 40),
                          const SizedBox(height: 6),
                          const Text(
                            "Nhiệt độ phòng",
                            style:
                            TextStyle(color: Colors.white, fontSize: 20),
                          ),
                          Text(
                            temperature,
                            style: const TextStyle(
                              color: Colors.yellow,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 25),

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
                          fanOn ? Icons.power_settings_new : Icons.power_off,
                          size: 50,
                          color: fanOn ? Colors.black : Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

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
                  enabledBorder:
                  OutlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                  focusedBorder:
                  OutlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
