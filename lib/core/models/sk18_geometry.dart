import 'dart:ui' show Rect;

import 'device_model_registry.dart';
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

/// Supported Waveshare LCD mechanical macro pad models running Protocol V2.
enum WaveshareModel {
  sk18('SK18'),
  mk10('MK10');

  final String code;

  const WaveshareModel(this.code);

  static WaveshareModel fromString(String? raw) =>
      DeviceModelRegistry.instance.fromCode(raw);

  DeviceModelSpec get spec => DeviceModelRegistry.instance.of(this).spec;
}

/// Immutable hardware specification for a Waveshare macro pad model.
class DeviceModelSpec {
  final WaveshareModel model;
  final int totalKeys;
  final int landscapeWidth;
  final int landscapeHeight;
  final int landscapeCols;
  final int landscapeRows;
  final int portraitWidth;
  final int portraitHeight;
  final int portraitCols;
  final int portraitRows;
  final int keyWidth;
  final int keyHeight;
  final int gapX;
  final int gapY;
  final int landscapeStartX;
  final int landscapeStartY;
  final int portraitStartX;
  final int portraitStartY;
  final bool requiresFirmwareMarginFix;
  final bool hasDedicatedStatusRegion;
  final double cornerRadius;
  final double borderWidth;
  final Rect? statusRegionRectLandscape;
  final Rect? statusRegionRectPortrait;
  final double? statusRegionCornerRadius;

  const DeviceModelSpec({
    required this.model,
    required this.totalKeys,
    required this.landscapeWidth,
    required this.landscapeHeight,
    required this.landscapeCols,
    required this.landscapeRows,
    required this.portraitWidth,
    required this.portraitHeight,
    required this.portraitCols,
    required this.portraitRows,
    required this.keyWidth,
    required this.keyHeight,
    required this.gapX,
    required this.gapY,
    required this.landscapeStartX,
    required this.landscapeStartY,
    required this.portraitStartX,
    required this.portraitStartY,
    required this.requiresFirmwareMarginFix,
    required this.hasDedicatedStatusRegion,
    required this.cornerRadius,
    required this.borderWidth,
    this.statusRegionRectLandscape,
    this.statusRegionRectPortrait,
    this.statusRegionCornerRadius,
  });

  int get pitchX => keyWidth + gapX;

  int get pitchY => keyHeight + gapY;

  String get displayName => model.code;

  static const DeviceModelSpec sk18 = DeviceModelSpec(
    model: WaveshareModel.sk18,
    totalKeys: 18,
    landscapeWidth: 1280,
    landscapeHeight: 720,
    landscapeCols: 6,
    landscapeRows: 3,
    portraitWidth: 720,
    portraitHeight: 1280,
    portraitCols: 3,
    portraitRows: 6,
    keyWidth: 158,
    keyHeight: 158,
    gapX: 60,
    gapY: 60,
    landscapeStartX: 22,
    landscapeStartY: 63,
    portraitStartX: 63,
    portraitStartY: 22,
    requiresFirmwareMarginFix: true,
    hasDedicatedStatusRegion: false,
    cornerRadius: 30,
    borderWidth: 2,
  );

  /// MK10 hardware spec verified against the stock `KeyboardDevice` (`V2.32`)
  /// `foregroundParam` init (`_GLOBAL__sub_I_main.cpp`, `MK10_V1.0.img`):
  /// the firmware reports an `896x304` (landscape) / `304x896` (portrait)
  /// panel — both dimensions are multiples of `16`, which the CedarX hardware
  /// JPEG decoder requires — with a `5x2` grid of `128 px` keys packed
  /// `1:1` from the panel origin (no gutters) and a dedicated `240x296`
  /// (landscape, at `x = 656`) / `296x240` (portrait, at `y = 0`) side screen.
  static const DeviceModelSpec mk10 = DeviceModelSpec(
    model: WaveshareModel.mk10,
    totalKeys: 10,
    landscapeWidth: 896,
    landscapeHeight: 304,
    landscapeCols: 5,
    landscapeRows: 2,
    portraitWidth: 304,
    portraitHeight: 896,
    portraitCols: 2,
    portraitRows: 5,
    keyWidth: 128,
    keyHeight: 128,
    gapX: 0,
    gapY: 0,
    landscapeStartX: 0,
    landscapeStartY: 0,
    portraitStartX: 0,
    portraitStartY: 256,
    requiresFirmwareMarginFix: false,
    hasDedicatedStatusRegion: true,
    cornerRadius: 15,
    borderWidth: 5,
    statusRegionRectLandscape: Rect.fromLTWH(656, 0, 240, 296),
    statusRegionRectPortrait: Rect.fromLTWH(0, 0, 296, 240),
    statusRegionCornerRadius: 40,
  );
}

/// Hardware pixel geometry and coordinate transformation rules for the
/// Waveshare SK18 (18-key, 1280x720) and Waveshare MK10 (10-key, 896x304).
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

  /// Computes all physical key rectangles (`18` for SK18 or `10` for MK10),
  /// filtering out non-key status regions (`isKey: false`), automatically applying
  /// the `+12 px` firmware `V2.32` margin correction on SK18 when `rawDeviceRects`
  /// reports an unflipped `10` start offset along the 1280px axis, plus any
  /// user calibration offset (`offsetX`, `offsetY` in `-64..+64`).
  static List<Sk18KeyRect> computeKeyRects({
    required bool isPortrait,
    List<Sk18KeyRect>? rawDeviceRects,
    int offsetX = 0,
    int offsetY = 0,
    WaveshareModel model = WaveshareModel.sk18,
  }) {
    final spec = model.spec;
    final dx = clampOffset(offsetX);
    final dy = clampOffset(offsetY);

    if (rawDeviceRects != null) {
      final keyOnlyRects = rawDeviceRects
          .where((r) => r.isKey)
          .toList(growable: false);
      if (keyOnlyRects.length == spec.totalKeys) {
        final needsXCorrection =
            spec.requiresFirmwareMarginFix &&
            !isPortrait &&
            keyOnlyRects.first.x == rawUnflippedLongAxisStart;
        final needsYCorrection =
            spec.requiresFirmwareMarginFix &&
            isPortrait &&
            keyOnlyRects.first.y == rawUnflippedLongAxisStart;

        final autoFixX = needsXCorrection ? firmwareMarginCorrection : 0;
        final autoFixY = needsYCorrection ? firmwareMarginCorrection : 0;

        return keyOnlyRects
            .map((rect) {
              return rect.copyWith(
                x: rect.x + autoFixX + dx,
                y: rect.y + autoFixY + dy,
              );
            })
            .toList(growable: false);
      }
    }

    final cols = isPortrait ? spec.portraitCols : spec.landscapeCols;
    final rows = isPortrait ? spec.portraitRows : spec.landscapeRows;
    final startX = isPortrait ? spec.portraitStartX : spec.landscapeStartX;
    final startY = isPortrait ? spec.portraitStartY : spec.landscapeStartY;

    final result = <Sk18KeyRect>[];
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        result.add(
          Sk18KeyRect(
            col: col,
            row: row,
            x: startX + spec.pitchX * col + dx,
            y: startY + spec.pitchY * row + dy,
            width: spec.keyWidth,
            height: spec.keyHeight,
            isKey: true,
          ),
        );
      }
    }
    return result;
  }

  /// Remaps incoming key events to logical coordinates.
  ///
  /// When operating in landscape mode (`authoringInLandscape = true`) on
  /// a physical SK18 (`3x6`) or MK10 (`2x5`) whose native panel scanout is portrait
  /// (`deviceIsPortrait = true`), the firmware emits `keyStateChanged` using portrait
  /// coordinates.
  ///
  /// Remapping formula for physical device events:
  ///   `logicalCol = physRow` (`0..landscapeCols-1`)
  ///   `logicalRow = (deviceRectCols - 1) - physCol` (`0..landscapeRows-1`)
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
    int? deviceRectCols,
    bool upsideDown = false,
    WaveshareModel model = WaveshareModel.sk18,
  }) {
    final spec = model.spec;
    final effectiveDeviceRectCols = deviceRectCols ?? spec.portraitCols;
    final cols = authoringInLandscape ? spec.landscapeCols : spec.portraitCols;
    final rows = authoringInLandscape ? spec.landscapeRows : spec.portraitRows;

    int logicalCol;
    int logicalRow;

    if (fromPhysicalDevice && deviceIsPortrait && authoringInLandscape) {
      logicalCol = row.clamp(0, spec.landscapeCols - 1);
      logicalRow = ((effectiveDeviceRectCols - 1) - col).clamp(
        0,
        spec.landscapeRows - 1,
      );
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

  /// Hit-tests a logical canvas point `(px, py)` against the model's key rectangles.
  /// Returns the key index if inside a key, or `null` if in a margin/gutter/status area.
  static int? hitTestKey({
    required double px,
    required double py,
    required bool isPortrait,
    List<Sk18KeyRect>? rawDeviceRects,
    int offsetX = 0,
    int offsetY = 0,
    WaveshareModel model = WaveshareModel.sk18,
  }) {
    final rects = computeKeyRects(
      isPortrait: isPortrait,
      rawDeviceRects: rawDeviceRects,
      offsetX: offsetX,
      offsetY: offsetY,
      model: model,
    );
    for (int i = 0; i < rects.length; i++) {
      if (rects[i].containsPoint(px, py)) {
        return i;
      }
    }
    return null;
  }
}
