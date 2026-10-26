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

    test('remaps physical events with 180-degree inversion when upsideDown is true', () {
      // When the physical SK18 is placed upside down on the desk, the physical switch
      // at the user's top-left is portrait col=0, row=5 (unflipped K18), which remaps to K1 (index 0).
      final invertedTopLeft = Sk18Geometry.remapKeyEvent(
        col: 0,
        row: 5,
        fromPhysicalDevice: true,
        deviceIsPortrait: true,
        authoringInLandscape: true,
        deviceRectCols: 3,
        upsideDown: true,
      );
      expect(invertedTopLeft.col, equals(0));
      expect(invertedTopLeft.row, equals(0));
      expect(invertedTopLeft.index, equals(0));

      // Portrait col=2, row=0 (unflipped K1) remaps to K18 (col=5, row=2, index=17) when upside down.
      final invertedBottomRight = Sk18Geometry.remapKeyEvent(
        col: 2,
        row: 0,
        fromPhysicalDevice: true,
        deviceIsPortrait: true,
        authoringInLandscape: true,
        deviceRectCols: 3,
        upsideDown: true,
      );
      expect(invertedBottomRight.col, equals(5));
      expect(invertedBottomRight.row, equals(2));
      expect(invertedBottomRight.index, equals(17));

      // Simulated desktop preview click is never inverted even when upsideDown is true.
      final simulatedWithUpsideDown = Sk18Geometry.remapKeyEvent(
        col: 1,
        row: 0,
        fromPhysicalDevice: false,
        deviceIsPortrait: true,
        authoringInLandscape: true,
        deviceRectCols: 3,
        upsideDown: true,
      );
      expect(simulatedWithUpsideDown.col, equals(1));
      expect(simulatedWithUpsideDown.row, equals(0));
      expect(simulatedWithUpsideDown.index, equals(1));
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

    test('computes exact MK10 landscape (896x304, 5x2) and portrait (304x896, 2x5) coordinates', () {
      // Stock V2.32 MK10: 128 px keys packed 1:1 from the panel origin
      // (no gutters); portrait keys start below the 296x240 side screen (y = 256).
      final landscapeRects = Sk18Geometry.computeKeyRects(
        isPortrait: false,
        model: WaveshareModel.mk10,
      );
      expect(landscapeRects.length, equals(10));

      final expectedLandscapeX = [0, 128, 256, 384, 512];
      final expectedLandscapeY = [0, 128];

      for (int row = 0; row < 2; row++) {
        for (int col = 0; col < 5; col++) {
          final index = row * 5 + col;
          final r = landscapeRects[index];
          expect(r.col, equals(col));
          expect(r.row, equals(row));
          expect(r.x, equals(expectedLandscapeX[col]));
          expect(r.y, equals(expectedLandscapeY[row]));
          expect(r.width, equals(128));
          expect(r.height, equals(128));
        }
      }

      final portraitRects = Sk18Geometry.computeKeyRects(
        isPortrait: true,
        model: WaveshareModel.mk10,
      );
      expect(portraitRects.length, equals(10));

      final expectedPortraitX = [0, 128];
      final expectedPortraitY = [256, 384, 512, 640, 768];

      for (int row = 0; row < 5; row++) {
        for (int col = 0; col < 2; col++) {
          final index = row * 2 + col;
          final r = portraitRects[index];
          expect(r.col, equals(col));
          expect(r.row, equals(row));
          expect(r.x, equals(expectedPortraitX[col]));
          expect(r.y, equals(expectedPortraitY[row]));
          expect(r.width, equals(128));
          expect(r.height, equals(128));
        }
      }
    });

    test('filters out non-key status rect (isKey: false) on MK10 and does not apply +12 px fix', () {
      final mk10Portrait = Sk18DeviceInfo.defaultMk10Portrait();
      expect(mk10Portrait.model, equals(WaveshareModel.mk10));
      expect(mk10Portrait.rects.length, equals(11)); // 1 status rect + 10 keys
      expect(mk10Portrait.rects.first.isKey, isFalse);

      final computedPortrait = Sk18Geometry.computeKeyRects(
        isPortrait: true,
        rawDeviceRects: mk10Portrait.rects,
        model: WaveshareModel.mk10,
      );
      expect(computedPortrait.length, equals(10));
      expect(computedPortrait.first.x, equals(0));
      expect(computedPortrait.first.y, equals(256));

      final mk10Landscape = Sk18DeviceInfo.defaultMk10Landscape();
      final computedLandscape = Sk18Geometry.computeKeyRects(
        isPortrait: false,
        rawDeviceRects: mk10Landscape.rects,
        model: WaveshareModel.mk10,
      );
      expect(computedLandscape.length, equals(10));
      expect(computedLandscape.first.x, equals(0));
      expect(computedLandscape.first.y, equals(0));
    });

    test('remaps MK10 physical portrait events (2x5) to logical landscape (5x2) including upsideDown', () {
      // Physical top-left landscape key K1 (logical col=0, row=0) on MK10 portrait (2 cols x 5 rows)
      // corresponds to portrait col=1, row=0 because logicalRow = (2 - 1) - physCol = 1 - 1 = 0.
      final mk10TopLeft = Sk18Geometry.remapKeyEvent(
        col: 1,
        row: 0,
        fromPhysicalDevice: true,
        deviceIsPortrait: true,
        authoringInLandscape: true,
        model: WaveshareModel.mk10,
      );
      expect(mk10TopLeft.col, equals(0));
      expect(mk10TopLeft.row, equals(0));
      expect(mk10TopLeft.index, equals(0));

      // Physical bottom-right landscape key K10 (logical col=4, row=1) corresponds to portrait col=0, row=4.
      final mk10BottomRight = Sk18Geometry.remapKeyEvent(
        col: 0,
        row: 4,
        fromPhysicalDevice: true,
        deviceIsPortrait: true,
        authoringInLandscape: true,
        model: WaveshareModel.mk10,
      );
      expect(mk10BottomRight.col, equals(4));
      expect(mk10BottomRight.row, equals(1));
      expect(mk10BottomRight.index, equals(9));

      // Upside-down MK10 inverts portrait col=0, row=4 to K1 (col=0, row=0, index=0).
      final mk10InvertedTopLeft = Sk18Geometry.remapKeyEvent(
        col: 0,
        row: 4,
        fromPhysicalDevice: true,
        deviceIsPortrait: true,
        authoringInLandscape: true,
        upsideDown: true,
        model: WaveshareModel.mk10,
      );
      expect(mk10InvertedTopLeft.col, equals(0));
      expect(mk10InvertedTopLeft.row, equals(0));
      expect(mk10InvertedTopLeft.index, equals(0));
    });
  });
}
