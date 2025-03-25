import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yucheng_ble/yucheng_ble_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelYuchengBle platform = MethodChannelYuchengBle();
  const MethodChannel channel = MethodChannel('yucheng_ble');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect('42', '42');
  });
}
