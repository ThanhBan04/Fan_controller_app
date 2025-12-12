// Code chạy oke, copy lại cho yên tâm ^^
// Code chỉ mới có publish topic lên cloud
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

enum MqttCurrentConnectionState {
  idle,
  connecting,
  connected,
  disconnected,
  errorWhenConnecting,
}

enum MqttSubscriptionState {
  idle,
  subscribed,
}

class MQTTClientWrapper {
  late MqttServerClient client;

  MqttCurrentConnectionState connectionState =
      MqttCurrentConnectionState.idle;
  MqttSubscriptionState subscriptionState =
      MqttSubscriptionState.idle;

  // Định nghĩa 4 topic
  static const String topicRoomTemp = 'iot/room/temp';
  static const String topicFanState = 'iot/fan/state';
  static const String topicFanSpeed = 'iot/fan/speed';
  static const String topicFanOsc = 'iot/fan/osc';

  Future<void> prepareMqttClient() async {
    _setupMqttClient();
    await _connectClient();
    _subscribeToTopics(); // subscribe 4 topic
    // Có thể test publish ở đây nếu muốn
    // publishFanState('ON');
  }

  void _setupMqttClient() {
    client = MqttServerClient.withPort(
      '099f0f049a6d49bca9614e32470c2276.s1.eu.hivemq.cloud', // host
      'flutter_fan_client', // clientID
      8883, // port TLS
    );

    client.secure = true;
    client.securityContext = SecurityContext.defaultContext;

    client.keepAlivePeriod = 20;
    client.logging(on: true);

    client.onDisconnected = _onDisconnected;
    client.onConnected = _onConnected;
    client.onSubscribed = _onSubscribed;
  }

  Future<void> _connectClient() async {
    try {
      print('Client connecting...');
      connectionState = MqttCurrentConnectionState.connecting;

      await client.connect('Thanh_Ban_04', 'Tb123456');
    } on Exception catch (e) {
      print('Client exception - $e');
      connectionState = MqttCurrentConnectionState.errorWhenConnecting;
      client.disconnect();
    }

    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      connectionState = MqttCurrentConnectionState.connected;
      print('Client connected');
    } else {
      print(
          'ERROR client connection failed - disconnecting, status is ${client.connectionStatus}');
      connectionState = MqttCurrentConnectionState.errorWhenConnecting;
      client.disconnect();
    }
  }

  void _subscribeToTopics() {
    final topics = <String>[
      topicRoomTemp,
      topicFanState,
      topicFanSpeed,
      topicFanOsc,
    ];

    for (final t in topics) {
      print('Subscribing to topic $t');
      client.subscribe(t, MqttQos.atMostOnce);
    }

    client.updates?.listen(
          (List<MqttReceivedMessage<MqttMessage>> c) {
        final MqttPublishMessage recMess =
        c[0].payload as MqttPublishMessage;
        final message = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );
        final topic = c[0].topic;

        print('YOU GOT A NEW MESSAGE ON TOPIC [$topic]: $message');

        // Tùy topic mà xử lý khác nhau
        switch (topic) {
          case topicRoomTemp:
          // xử lý nhiệt độ phòng, ví dụ parse double
          // final temp = double.tryParse(message);
            print('Room temp message: $message');
            break;

          case topicFanState:
          // xử lý trạng thái quạt ON/OFF
            print('Fan state message: $message');
            break;

          case topicFanSpeed:
          // xử lý tốc độ quạt (ví dụ 0-3)
            print('Fan speed message: $message');
            break;

          case topicFanOsc:
          // xử lý chế độ đảo gió ON/OFF
            print('Fan osc message: $message');
            break;

          default:
            print('Message from unknown topic: $topic');
        }
      },
    );
  }

  // ====== PUBLISH HÀM CHUNG ======
  void _publishMessage(String topic, String message,
      {MqttQos qos = MqttQos.exactlyOnce}) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);

    print('Publishing message "$message" to topic $topic');
    client.publishMessage(
      topic,
      qos,
      builder.payload!,
    );
  }

  // ====== PUBLISH HÀM RIÊNG TỪNG TOPIC ======

  /// Gửi nhiệt độ phòng, ví dụ: "27.5"
  void publishRoomTemp(String temp) {
    _publishMessage(topicRoomTemp, temp);
  }

  /// Gửi trạng thái quạt: "ON" hoặc "OFF"
  void publishFanState(String state) {
    _publishMessage(topicFanState, state);
  }

  /// Gửi tốc độ quạt, ví dụ: "0", "1", "2", "3"
  void publishFanSpeed(String speed) {
    _publishMessage(topicFanSpeed, speed);
  }

  /// Gửi trạng thái đảo gió: "ON" hoặc "OFF"
  void publishFanOsc(String oscState) {
    _publishMessage(topicFanOsc, oscState);
  }

  // Nếu vẫn muốn hàm cũ thì có thể giữ lại, nhưng giờ nên chỉ rõ topic:
  void publishRaw(String topic, String message) {
    _publishMessage(topic, message);
  }

  void _onSubscribed(String topic) {
    print('Subscription confirmed for topic $topic');
    subscriptionState = MqttSubscriptionState.subscribed;
  }

  void _onDisconnected() {
    print('OnDisconnected client callback - Client disconnection');
    connectionState = MqttCurrentConnectionState.disconnected;
  }

  void _onConnected() {
    connectionState = MqttCurrentConnectionState.connected;
    print('OnConnected client callback - Client connection was successful');
  }
}
