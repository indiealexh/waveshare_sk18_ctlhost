import 'sk18_device_info.dart';

class Sk18KeyCoord {
  final int index;
  final int col;
  final int row;

  const Sk18KeyCoord({
    required this.index,
    required this.col,
    required this.row,
  });

  @override
  bool operator ==(Object other) {
    return other is Sk18KeyCoord &&
        other.index == index &&
        other.col == col &&
        other.row == row;
  }

  @override
  int get hashCode => Object.hash(index, col, row);

  @override
  String toString() => 'Sk18KeyCoord(index: $index, col: $col, row: $row)';
}

/// Hardware pixel geometry and coordinate transformation rules for the
/// Waveshare SK18 (18-key mechanical macro pad with 1280x720 / 720x1280 IPS LCD).
class Sk18Geometry {
  static const int totalKeys = 18;

  static const int landscapeWidth = 1280;
  static const int landscapeHeight = 720;
  static const int landscapeCols = 6;
  static const int landscapeRows = 3;

  static const int portraitWidth = 720;
  static const int portraitHeight = 1280;
  static const int portraitCols = 3;
  static const int portraitRows = 6;

  static const int keyWidth = 158;
  static const int keyHeight = 158;
  static const int gapX = 60;
  static const int gapY = 60;
  static const int pitch = 218; // 158 + 60
  static const double cornerRadius = 30.0;
  static const double borderWidth = 2.0;

  /// Physical corrected margins along the 1280px axis (`22px` on one side, `10px` on the other).
  static const int correctedLongAxisStart = 22;
  static const int rawUnflippedLongAxisStart = 10;
  static const int firmwareMarginCorrection = 12; // 22 - 10

  /// Symmetric margin along the 720px axis (`63 + 3*158 + 2*60 + 63 = 720`).
  static const int shortAxisStart = 63;

  static const int minCalibrationOffset = -64;
  static const int maxCalibrationOffset = 64;

  const Sk18Geometry._();

  static int clampOffset(int offset) {
    return offset.clamp(minCalibrationOffset, maxCalibrationOffset);
  }

  /// Computes all 18 physical key rectangles (`158x158`), automatically applying
  /// the `+12 px` firmware `V2.32` margin correction when `rawDeviceRects`
  /// reports an unflipped `10` start offset along the 1280px axis, plus any
  /// user calibration offset (`offsetX`, `offsetY` in `-64..+64`).
  static List<Sk18KeyRect> computeKeyRects({
    required bool isPortrait,
    List<Sk18KeyRect>? rawDeviceRects,
    int offsetX = 0,
    int offsetY = 0,
  }) {
    final dx = clampOffset(offsetX);
    final dy = clampOffset(offsetY);

    if (rawDeviceRects != null && rawDeviceRects.length == totalKeys) {
      final needsXCorrection = !isPortrait && rawDeviceRects.first.x == rawUnflippedLongAxisStart;
      final needsYCorrection = isPortrait && rawDeviceRects.first.y == rawUnflippedLongAxisStart;

      final autoFixX = needsXCorrection ? firmwareMarginCorrection : 0;
      final autoFixY = needsYCorrection ? firmwareMarginCorrection : 0;

      return rawDeviceRects.map((rect) {
        return rect.copyWith(
          x: rect.x + autoFixX + dx,
          y: rect.y + autoFixY + dy,
        );
      }).toList(growable: false);
    }

    final cols = isPortrait ? portraitCols : landscapeCols;
    final rows = isPortrait ? portraitRows : landscapeRows;
    final startX = isPortrait ? shortAxisStart : correctedLongAxisStart;
    final startY = isPortrait ? correctedLongAxisStart : shortAxisStart;

    final result = <Sk18KeyRect>[];
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        result.add(
          Sk18KeyRect(
            col: col,
            row: row,
            x: startX + pitch * col + dx,
            y: startY + pitch * row + dy,
            width: keyWidth,
            height: keyHeight,
            isKey: true,
          ),
        );
      }
    }
    return result;
  }

  /// Remaps incoming key events to logical coordinates.
  ///
  /// When operating in landscape mode (`authoringInLandscape = true`, `6x3`) on
  /// a physical SK18 whose native panel scanout is portrait (`deviceIsPortrait = true`, `3x6`),
  /// the firmware emits `keyStateChanged` using portrait coordinates (`physCol in 0..2`, `physRow in 0..5`).
  ///
  /// Remapping formula for physical device events:
  ///   `logicalCol = physRow` (`0..5`)
  ///   `logicalRow = (deviceRectCols - 1) - physCol` (`2 - physCol`, `0..2`)
  ///
  /// When `upsideDown = true`, physical device coordinates are additionally inverted
  /// 180° (`col = cols - 1 - col`, `row = rows - 1 - row`) so `K1` stays at the
  /// top-left of a physically inverted device.
  ///
  /// Simulated button clicks from the desktop UI preview (`fromPhysicalDevice: false`)
  /// are NEVER remapped.
  static Sk18KeyCoord remapKeyEvent({
    required int col,
    required int row,
    required bool fromPhysicalDevice,
    bool deviceIsPortrait = true,
    bool authoringInLandscape = true,
    int deviceRectCols = portraitCols,
    bool upsideDown = false,
  }) {
    final cols = authoringInLandscape ? landscapeCols : portraitCols;
    final rows = authoringInLandscape ? landscapeRows : portraitRows;

    int logicalCol;
    int logicalRow;

    if (fromPhysicalDevice && deviceIsPortrait && authoringInLandscape) {
      logicalCol = row.clamp(0, landscapeCols - 1);
      logicalRow = ((deviceRectCols - 1) - col).clamp(0, landscapeRows - 1);
    } else {
      logicalCol = col.clamp(0, cols - 1);
      logicalRow = row.clamp(0, rows - 1);
    }

    if (fromPhysicalDevice && upsideDown) {
      logicalCol = (cols - 1) - logicalCol;
      logicalRow = (rows - 1) - logicalRow;
    }

    final index = logicalRow * cols + logicalCol;
    return Sk18KeyCoord(index: index, col: logicalCol, row: logicalRow);
  }

  /// Hit-tests a logical canvas point `(px, py)` against the 18 key rectangles.
  /// Returns the key index `0..17` if inside a key, or `null` if in a margin/gutter.
  static int? hitTestKey({
    required double px,
    required double py,
    required bool isPortrait,
    List<Sk18KeyRect>? rawDeviceRects,
    int offsetX = 0,
    int offsetY = 0,
  }) {
    final rects = computeKeyRects(
      isPortrait: isPortrait,
      rawDeviceRects: rawDeviceRects,
      offsetX: offsetX,
      offsetY: offsetY,
    );
    for (int i = 0; i < rects.length; i++) {
      if (rects[i].containsPoint(px, py)) {
        return i;
      }
    }
    return null;
  }
}
