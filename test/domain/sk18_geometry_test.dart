import 'package:flutter_test/flutter_test.dart';
import 'package:wavectl_host/domain/models/sk18_device_info.dart';
import 'package:wavectl_host/domain/models/sk18_geometry.dart';

void main() {
  group('Sk18Geometry', () {
    test('computes exact landscape coordinates (1280x720, 6x3)', () {
      final rects = Sk18Geometry.computeKeyRects(isPortrait: false);
      expect(rects.length, equals(18));

      final expectedX = [22, 240, 458, 676, 894, 1112];
      final expectedY = [63, 281, 499];

      for (int row = 0; row < 3; row++) {
        for (int col = 0; col < 6; col++) {
          final index = row * 6 + col;
          final r = rects[index];
          expect(r.col, equals(col));
          expect(r.row, equals(row));
          expect(r.x, equals(expectedX[col]));
          expect(r.y, equals(expectedY[row]));
          expect(r.width, equals(158));
          expect(r.height, equals(158));
        }
      }
    });

    test('computes exact portrait coordinates (720x1280, 3x6)', () {
      final rects = Sk18Geometry.computeKeyRects(isPortrait: true);
      expect(rects.length, equals(18));

      final expectedX = [63, 281, 499];
      final expectedY = [22, 240, 458, 676, 894, 1112];

      for (int row = 0; row < 6; row++) {
        for (int col = 0; col < 3; col++) {
          final index = row * 3 + col;
          final r = rects[index];
          expect(r.col, equals(col));
          expect(r.row, equals(row));
          expect(r.x, equals(expectedX[col]));
          expect(r.y, equals(expectedY[row]));
        }
      }
    });

    test('applies +12 px firmware margin auto-correction when raw x == 10 or y == 10', () {
      final rawLandscape = Sk18DeviceInfo.defaultLandscape();
      expect(rawLandscape.rects.first.x, equals(10));

      final correctedLandscape = Sk18Geometry.computeKeyRects(
        isPortrait: false,
        rawDeviceRects: rawLandscape.rects,
      );
      expect(correctedLandscape.first.x, equals(22));
      expect(correctedLandscape.first.y, equals(63));
      expect(correctedLandscape[5].x, equals(1112));

      final rawPortrait = Sk18DeviceInfo.defaultPortrait();
      expect(rawPortrait.rects.first.y, equals(10));

      final correctedPortrait = Sk18Geometry.computeKeyRects(
        isPortrait: true,
        rawDeviceRects: rawPortrait.rects,
      );
      expect(correctedPortrait.first.x, equals(63));
      expect(correctedPortrait.first.y, equals(22));
      expect(correctedPortrait.last.y, equals(1112));
    });

    test('applies user calibration offsets clamped to -64..+64', () {
      final rects = Sk18Geometry.computeKeyRects(
        isPortrait: false,
        offsetX: 100, // clamped to +64
        offsetY: -100, // clamped to -64
      );
      expect(rects.first.x, equals(22 + 64));
      expect(rects.first.y, equals(63 - 64));
    });

    test('remaps physical portrait events to logical landscape and leaves simulated clicks untouched', () {
      // Physical top-left landscape key K1 (logical col=0, row=0) corresponds to
      // portrait col=2, row=0 because logicalRow = 2 - physCol and logicalCol = physRow.
      final physicalRemapped = Sk18Geometry.remapKeyEvent(
        col: 2,
        row: 0,
        fromPhysicalDevice: true,
        deviceIsPortrait: true,
        authoringInLandscape: true,
        deviceRectCols: 3,
      );
      expect(physicalRemapped.col, equals(0));
      expect(physicalRemapped.row, equals(0));
      expect(physicalRemapped.index, equals(0));

      // Physical bottom-right landscape key K18 (logical col=5, row=2) corresponds to
      // portrait col=0, row=5.
      final physicalBottomRight = Sk18Geometry.remapKeyEvent(
        col: 0,
        row: 5,
        fromPhysicalDevice: true,
        deviceIsPortrait: true,
        authoringInLandscape: true,
        deviceRectCols: 3,
      );
      expect(physicalBottomRight.col, equals(5));
      expect(physicalBottomRight.row, equals(2));
      expect(physicalBottomRight.index, equals(17));

      // Simulated UI click in column 4, row 1 must NEVER be remapped!
      final simulatedClick = Sk18Geometry.remapKeyEvent(
        col: 4,
        row: 1,
        fromPhysicalDevice: false,
        deviceIsPortrait: true,
        authoringInLandscape: true,
        deviceRectCols: 3,
      );
      expect(simulatedClick.col, equals(4));
      expect(simulatedClick.row, equals(1));
      expect(simulatedClick.index, equals(10));
    });

    test('hitTestKey identifies key index or returns null in gutters/margins', () {
      expect(
        Sk18Geometry.hitTestKey(px: 100, py: 100, isPortrait: false),
        equals(0),
      );
      // Inside horizontal gutter between col 0 (22..179) and col 1 (240..397)
      expect(
        Sk18Geometry.hitTestKey(px: 200, py: 100, isPortrait: false),
        isNull,
      );
      // Last key K18 (col 5, row 2) -> x=1112..1269, y=499..656
      expect(
        Sk18Geometry.hitTestKey(px: 1150, py: 550, isPortrait: false),
        equals(17),
      );
    });
  });
}
