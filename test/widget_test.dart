import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixel_compass/main.dart';

void main() {
  test('frame 0 points down, frame 32 points up', () {
    expect(frameForAngle(180), 0);
    expect(frameForAngle(0), 32);
    expect(frameForAngle(90), 48);
    expect(frameForAngle(270), 16);
  });

  test('cardinal names', () {
    expect(cardinal(0), 'N');
    expect(cardinal(359), 'N');
    expect(cardinal(90), 'E');
    expect(cardinal(225), 'SW');
  });

  testWidgets('shows heading from the compass stream', (tester) async {
    final events = Stream<CompassEvent>.value(
      CompassEvent.fromList([90.0, 90.0, 10.0]),
    );
    await tester.pumpWidget(CompassApp(events: events));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('90°'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);
  });
}
