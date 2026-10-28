import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../features/actions/domain/action_plugin.dart';
import '../../features/actions/domain/action_plugin_registry.dart';
import '../../features/actions/domain/button_action.dart';
import '../../features/home_assistant/domain/ha_entity_state.dart';
import '../../features/profiles/domain/key_button_config.dart';
import '../models/sk18_device_info.dart';
import '../models/sk18_geometry.dart';
import '../../features/profiles/domain/sk18_profile.dart';

class Sk18RawFrameBuffer {
  final int width;
  final int height;
  final Uint8List rgbaBytes;

  const Sk18RawFrameBuffer({
    required this.width,
    required this.height,
    required this.rgbaBytes,
  });
}

class Sk18IconCatalog {
  static const Map<String, IconData> icons = <String, IconData>{
    'lightbulb': Icons.lightbulb_rounded,
    'sun': Icons.wb_sunny_rounded,
    'moon': Icons.nightlight_round,
    'thermostat': Icons.thermostat_rounded,
    'temp_up': Icons.keyboard_arrow_up_rounded,
    'temp_down': Icons.keyboard_arrow_down_rounded,
    'terminal': Icons.terminal_rounded,
    'code': Icons.code_rounded,
    'globe': Icons.public_rounded,
    'copy': Icons.content_copy_rounded,
    'paste': Icons.content_paste_rounded,
    'bolt': Icons.bolt_rounded,
    'speaker': Icons.volume_up_rounded,
    'music': Icons.music_note_rounded,
    'mouse': Icons.mouse_rounded,
    'power': Icons.power_settings_new_rounded,
    'play': Icons.play_arrow_rounded,
    'grid': Icons.grid_view_rounded,
  };

  static List<String> get iconNames => icons.keys.toList(growable: false);

  static IconData resolve(String name) {
    switch (name) {
      case 'temp_up':
        return Icons.keyboard_arrow_up_rounded;
      case 'temp_down':
        return Icons.keyboard_arrow_down_rounded;
      default:
        return icons[name] ?? Icons.bolt_rounded;
    }
  }
}

/// Shared dual-path canvas renderer used by both the 60 FPS desktop `CustomPainter`
/// and the offscreen `ui.PictureRecorder` hardware frame generator.
class Sk18CanvasRenderer {
  const Sk18CanvasRenderer._();

  /// Paints the logical SK18 (`1280x720` / `720x1280`) or MK10 (`896x304` / `304x896`) LCD canvas.
  static void paintLogicalCanvas(
    Canvas canvas,
    Size size, {
    required Sk18Page page,
    required bool isPortrait,
    WaveshareModel model = WaveshareModel.sk18,
    bool upsideDown = false,
    Map<String, HaEntityState> haEntities = const {},
    Set<int> pressedKeyIndices = const {},
    int? selectedKeyIndex,
    List<Sk18KeyRect>? rawDeviceRects,
    int offsetX = 0,
    int offsetY = 0,
    String profileName = 'SK18 Studio',
    String statusText = 'READY',
    String clockString = '12:00',
    bool showDesktopSelectionOutline = false,
  }) {
    final fullRect = Offset.zero & size;

    // 1. Deep slate LCD background with subtle radial studio glow
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, size.height),
        const [Color(0xFF0B1120), Color(0xFF111827), Color(0xFF0F172A)],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(fullRect, bgPaint);

    // 2. Status / telemetry region:
    //    - MK10: dedicated side screen (240x296 at x=656 landscape,
    //            296x240 at top portrait) status dashboard region
    //    - SK18: slim 63 px top margin telemetry band
    if (model == WaveshareModel.mk10) {
      _paintMk10RichStatusRegion(
        canvas,
        size,
        isPortrait: isPortrait,
        upsideDown: upsideDown,
        profileName: profileName,
        pageName: page.name,
        statusText: statusText,
        clockString: clockString,
        offsetX: offsetX,
        offsetY: offsetY,
        haEntities: haEntities,
      );
    } else {
      if (upsideDown) {
        canvas.save();
        canvas.translate(size.width, size.height);
        canvas.rotate(math.pi);
      }
      _paintMarginTelemetryBands(
        canvas,
        size,
        isPortrait: isPortrait,
        profileName: profileName,
        pageName: page.name,
        statusText: statusText,
        clockString: clockString,
        offsetX: offsetX,
        offsetY: offsetY,
      );
      if (upsideDown) {
        canvas.restore();
      }
    }

    // 3. Compute exact physical key rectangles (18 for SK18, 10 for MK10)
    final keyRects = Sk18Geometry.computeKeyRects(
      isPortrait: isPortrait,
      rawDeviceRects: rawDeviceRects,
      offsetX: offsetX,
      offsetY: offsetY,
      model: model,
    );

    final spec = model.spec;
    final hasZeroGutter = spec.gapX == 0 || spec.gapY == 0;
    final tileInset = hasZeroGutter
        ? (spec.borderWidth / 2.0).ceilToDouble()
        : 0.0;
    final effectiveBorderWidth = hasZeroGutter
        ? Sk18Geometry.borderWidth
        : spec.borderWidth;

    final count = math.min(keyRects.length, page.keys.length);
    for (int i = 0; i < count; i++) {
      final rectIndex = upsideDown ? (count - 1 - i) : i;
      final rectModel = keyRects[rectIndex];
      final keyConfig = page.keys[i];
      final isPressed = pressedKeyIndices.contains(i);
      final isSelected = showDesktopSelectionOutline && selectedKeyIndex == i;
      final haState = keyConfig.action.category == ActionCategory.homeAssistant
          ? haEntities[keyConfig.action.entityId]
          : null;

      _paintKeyTile(
        canvas,
        rectModel: rectModel,
        keyConfig: keyConfig,
        haState: haState,
        isPressed: isPressed,
        isSelected: isSelected,
        upsideDown: upsideDown,
        cornerRadius: spec.cornerRadius,
        borderWidth: effectiveBorderWidth,
        tileInset: tileInset,
      );
    }
  }

  /// Renders the dedicated side-screen display region on the Waveshare MK10
  /// (`240x296` at `x = 656` in landscape, `296x240` at the top in portrait —
  /// verified against the stock `V2.32` `foregroundParam`) with model badge,
  /// digital clock, profile/page header, calibration label, and live Home
  /// Assistant telemetry sub-cards.
  static void _paintMk10RichStatusRegion(
    Canvas canvas,
    Size size, {
    required bool isPortrait,
    required bool upsideDown,
    required String profileName,
    required String pageName,
    required String statusText,
    required String clockString,
    required int offsetX,
    required int offsetY,
    required Map<String, HaEntityState> haEntities,
  }) {
    final spec = DeviceModelSpec.mk10;
    final regionRect = (isPortrait
            ? spec.statusRegionRectPortrait
            : spec.statusRegionRectLandscape)!;

    canvas.save();
    if (upsideDown) {
      canvas.translate(regionRect.center.dx, regionRect.center.dy);
      canvas.rotate(math.pi);
      canvas.translate(-regionRect.center.dx, -regionRect.center.dy);
    }

    final cardRect = regionRect.deflate(8);
    final cardRRect = RRect.fromRectAndRadius(
      cardRect,
      const Radius.circular(16),
    );

    final cardFill = Paint()
      ..shader = ui.Gradient.linear(
        cardRect.topLeft,
        cardRect.bottomRight,
        const [Color(0xFF1E293B), Color(0xFF0F172A)],
      );
    canvas.drawRRect(cardRRect, cardFill);

    final cardBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.35);
    canvas.drawRRect(cardRRect, cardBorder);

    final calLabel =
        'CAL (${offsetX >= 0 ? '+$offsetX' : '$offsetX'}, ${offsetY >= 0 ? '+$offsetY' : '$offsetY'})';
    final entityList = haEntities.values.take(3).toList(growable: false);

    // Row 1: model badge (left) + digital clock (right)
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cardRect.left + 10, cardRect.top + 10, 104, 24),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      badgeRect,
      Paint()..color = const Color(0xFF0284C7).withValues(alpha: 0.32),
    );
    _drawText(
      canvas,
      text: 'MK10 • 10-KEY',
      offset: Offset(cardRect.left + 10, cardRect.top + 16),
      maxWidth: 104,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF38BDF8),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
    _drawText(
      canvas,
      text: clockString,
      offset: Offset(cardRect.right - 110, cardRect.top + 10),
      maxWidth: 100,
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: Color(0xFFF8FAFC),
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    );

    // Row 2: profile name
    _drawText(
      canvas,
      text: profileName,
      offset: Offset(cardRect.left + 10, cardRect.top + 42),
      maxWidth: cardRect.width - 20,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFFE2E8F0),
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );

    // Row 3: page + connection status
    _drawText(
      canvas,
      text: '$pageName  •  $statusText',
      offset: Offset(cardRect.left + 10, cardRect.top + 62),
      maxWidth: cardRect.width - 20,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF34D399),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );

    // Row 4: panel spec + calibration
    _drawText(
      canvas,
      text: '896×304 IPS  •  $calLabel',
      offset: Offset(cardRect.left + 10, cardRect.top + 80),
      maxWidth: cardRect.width - 20,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );

    // Live Home Assistant entity sub-cards, stacked and clipped to the card
    for (int i = 0; i < entityList.length; i++) {
      final itemRect = Rect.fromLTWH(
        cardRect.left + 10,
        cardRect.top + 100 + i * 70.0,
        cardRect.width - 20,
        62,
      );
      if (itemRect.bottom > cardRect.bottom - 8) break;
      _paintMk10EntitySubCard(canvas, itemRect, entityList[i]);
    }

    canvas.restore();
  }

  static void _paintMk10EntitySubCard(
    Canvas canvas,
    Rect itemRect,
    HaEntityState entity,
  ) {
    final isActive = entity.isOn;
    final accent = switch (entity.domain) {
      'light' => const Color(0xFFF59E0B),
      'climate' => const Color(0xFF06B6D4),
      'switch' => const Color(0xFF10B981),
      _ => const Color(0xFF8B5CF6),
    };

    final subRRect = RRect.fromRectAndRadius(
      itemRect,
      const Radius.circular(14),
    );
    canvas.drawRRect(
      subRRect,
      Paint()
        ..color = isActive
            ? accent.withValues(alpha: 0.16)
            : const Color(0xFF0F172A).withValues(alpha: 0.78),
    );
    canvas.drawRRect(
      subRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = isActive
            ? accent.withValues(alpha: 0.75)
            : const Color(0xFF334155),
    );

    _drawText(
      canvas,
      text: entity.friendlyName,
      offset: Offset(itemRect.left + 12, itemRect.top + 10),
      maxWidth: itemRect.width - 24,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );

    String valueSummary = entity.state.toUpperCase();
    if (entity.brightnessPct != null) {
      valueSummary = '${entity.state.toUpperCase()}  •  ${entity.brightnessPct}%';
    } else if (entity.currentTemperature != null) {
      valueSummary =
          '${entity.state.toUpperCase()}  •  ${entity.currentTemperature!.toStringAsFixed(1)}°C';
    }

    _drawText(
      canvas,
      text: valueSummary,
      offset: Offset(itemRect.left + 12, itemRect.top + 30),
      maxWidth: itemRect.width - 24,
      style: TextStyle(
        color: isActive ? accent : const Color(0xFF94A3B8),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );

    _drawText(
      canvas,
      text: entity.entityId,
      offset: Offset(itemRect.left + 12, itemRect.top + 46),
      maxWidth: itemRect.width - 24,
      style: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static void _paintMarginTelemetryBands(
    Canvas canvas,
    Size size, {
    required bool isPortrait,
    required String profileName,
    required String pageName,
    required String statusText,
    required String clockString,
    required int offsetX,
    required int offsetY,
  }) {
    final topBandHeight = isPortrait ? 20.0 : 54.0;
    if (topBandHeight < 30) return;

    final barPaint = Paint()..color = const Color(0xFF1E293B).withValues(alpha: 0.72);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 46), barPaint);

    _drawText(
      canvas,
      text: '$profileName  •  $pageName',
      offset: const Offset(24, 13),
      maxWidth: size.width * 0.55,
      style: const TextStyle(
        color: Color(0xFFE2E8F0),
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );

    final rightLabel =
        '$statusText   |   CAL (${offsetX >= 0 ? '+$offsetX' : '$offsetX'}, ${offsetY >= 0 ? '+$offsetY' : '$offsetY'})   |   $clockString';
    _drawText(
      canvas,
      text: rightLabel,
      offset: Offset(size.width - 420, 14),
      maxWidth: 396,
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static void _paintKeyTile(
    Canvas canvas, {
    required Sk18KeyRect rectModel,
    required KeyButtonConfig keyConfig,
    required HaEntityState? haState,
    required bool isPressed,
    required bool isSelected,
    bool upsideDown = false,
    double cornerRadius = Sk18Geometry.cornerRadius,
    double borderWidth = Sk18Geometry.borderWidth,
    double tileInset = 0.0,
  }) {
    final baseRect = Rect.fromLTWH(
      rectModel.x.toDouble(),
      rectModel.y.toDouble(),
      rectModel.width.toDouble(),
      rectModel.height.toDouble(),
    );

    canvas.save();
    if (tileInset > 0.0) {
      canvas.clipRect(baseRect);
    }
    if (upsideDown) {
      canvas.translate(baseRect.center.dx, baseRect.center.dy);
      canvas.rotate(math.pi);
      canvas.translate(-baseRect.center.dx, -baseRect.center.dy);
    }

    final tileRect = tileInset > 0.0 ? baseRect.deflate(tileInset) : baseRect;
    final pressDeflate = tileInset > 0.0 ? 2.0 : 3.0;
    final effectiveTileRect = isPressed
        ? tileRect.deflate(pressDeflate)
        : tileRect;
    final rrect = RRect.fromRectAndRadius(
      effectiveTileRect,
      Radius.circular(cornerRadius),
    );

    final accentColor = Color(keyConfig.colorHex);
    final isHaActive = haState?.isOn ?? false;
    final action = keyConfig.action;
    final plugin = ActionPluginRegistry.instance.forCategory(action.category);

    // Keycap background gradient
    final tileFillPaint = Paint()
      ..shader = ui.Gradient.linear(
        effectiveTileRect.topLeft,
        effectiveTileRect.bottomRight,
        [
          isPressed
              ? accentColor.withValues(alpha: 0.42)
              : accentColor.withValues(alpha: isHaActive ? 0.28 : 0.16),
          const Color(0xFF1E293B),
        ],
      );
    canvas.drawRRect(rrect, tileFillPaint);

    // Active HA or Pressed glow border (inset by half strokeWidth so the stroke
    // stays strictly inside effectiveTileRect and never bleeds into neighbors)
    final strokeWidth = (isPressed || isHaActive)
        ? (tileInset > 0.0 ? 3.0 : 3.5)
        : borderWidth;
    final halfStroke = strokeWidth / 2.0;
    final borderRRect = RRect.fromRectAndRadius(
      effectiveTileRect.deflate(halfStroke),
      Radius.circular(math.max(0.0, cornerRadius - halfStroke)),
    );
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = isPressed
          ? Colors.white
          : (isHaActive
                ? accentColor
                : accentColor.withValues(alpha: 0.55));
    canvas.drawRRect(borderRRect, borderPaint);

    // Desktop studio selection ring
    if (isSelected) {
      final selectStrokeWidth = tileInset > 0.0 ? 2.0 : 2.5;
      final selectRRect = tileInset > 0.0
          ? RRect.fromRectAndRadius(
              baseRect.deflate(selectStrokeWidth / 2.0),
              Radius.circular(cornerRadius + (tileInset - selectStrokeWidth / 2.0)),
            )
          : RRect.fromRectAndRadius(
              baseRect.inflate(4.0),
              Radius.circular(cornerRadius + 4.0),
            );
      final selectPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selectStrokeWidth
        ..color = const Color(0xFF38BDF8);
      canvas.drawRRect(selectRRect, selectPaint);
    }

    // Top-left key slot number (K1..K18)
    _drawText(
      canvas,
      text: 'K${keyConfig.index + 1}',
      offset: Offset(baseRect.left + 14, baseRect.top + 12),
      maxWidth: 48,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );

    // Top-right category / telemetry pill
    final pillText =
        plugin.topRightPill(action, haState) ?? plugin.summaryBadge(action);
    final pillBgColor = (haState != null && haState.isOn)
        ? const Color(0xFF10B981)
        : const Color(0xFF334155);
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(baseRect.right - 64, baseRect.top + 10, 52, 20),
      const Radius.circular(10),
    );
    canvas.drawRRect(pillRect, Paint()..color = pillBgColor);
    _drawText(
      canvas,
      text: pillText,
      offset: Offset(baseRect.right - 62, baseRect.top + 13),
      maxWidth: 48,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    );

    // Center Vector Icon
    final isCompactTile = baseRect.height <= 144.0;
    final iconData = Sk18IconCatalog.resolve(keyConfig.iconName);
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: isCompactTile ? 34 : 38,
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: isPressed ? Colors.white : accentColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
      canvas,
      Offset(
        baseRect.center.dx - iconPainter.width / 2,
        baseRect.top + (isCompactTile ? 36 : 42),
      ),
    );

    // Live Home Assistant telemetry bar or sub-status
    plugin.paintKeyTelemetry(
      canvas,
      KeyTelemetryPaintContext(
        baseRect: baseRect,
        action: action,
        haState: haState,
        accentColor: accentColor,
      ),
    );

    // Bottom Key Label
    _drawText(
      canvas,
      text: keyConfig.label,
      offset: Offset(
        baseRect.left + 10,
        baseRect.bottom - (isCompactTile ? 30 : 34),
      ),
      maxWidth: baseRect.width - 20,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: isCompactTile ? 13.5 : 15,
        fontWeight: FontWeight.w700,
      ),
    );

    canvas.restore();
  }

  static void _drawText(
    Canvas canvas, {
    required String text,
    required Offset offset,
    required double maxWidth,
    required TextStyle style,
    TextAlign textAlign = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      maxLines: 1,
      ellipsis: '…',
    )..layout(minWidth: maxWidth, maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  /// Rasterizes the SK18 or MK10 canvas offscreen into raw RGBA bytes.
  ///
  /// When authoring in landscape (`1280x720` on SK18 or `896x304` on MK10) and
  /// streaming to a portrait-scanout device (`rotateForPortraitDevice = true`),
  /// this pre-rotates the `Canvas` 90° clockwise on the GPU:
  ///   `canvas.translate(portraitWidth, 0); canvas.rotate(math.pi / 2);`
  /// prior to `Picture.toImage(portraitWidth, portraitHeight)`, eliminating CPU `copyRotate` overhead.
  static Future<Sk18RawFrameBuffer> renderOffscreenRgba({
    required Sk18Page page,
    required bool authoringInLandscape,
    required bool rotateForPortraitDevice,
    WaveshareModel model = WaveshareModel.sk18,
    bool upsideDown = false,
    Map<String, HaEntityState> haEntities = const {},
    Set<int> pressedKeyIndices = const {},
    List<Sk18KeyRect>? rawDeviceRects,
    int offsetX = 0,
    int offsetY = 0,
    String profileName = 'SK18 Studio',
    String statusText = 'LIVE',
    String clockString = '12:00',
  }) async {
    final spec = model.spec;
    final recorder = ui.PictureRecorder();

    if (authoringInLandscape && rotateForPortraitDevice) {
      final targetWidth = spec.portraitWidth;
      final targetHeight = spec.portraitHeight;
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
      );

      // Pre-rotate on the GPU: 90 degrees clockwise
      canvas.translate(targetWidth.toDouble(), 0);
      canvas.rotate(math.pi / 2);

      paintLogicalCanvas(
        canvas,
        Size(spec.landscapeWidth.toDouble(), spec.landscapeHeight.toDouble()),
        page: page,
        isPortrait: false,
        model: model,
        upsideDown: upsideDown,
        haEntities: haEntities,
        pressedKeyIndices: pressedKeyIndices,
        rawDeviceRects: null,
        offsetX: offsetX,
        offsetY: offsetY,
        profileName: profileName,
        statusText: statusText,
        clockString: clockString,
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(targetWidth, targetHeight);
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      image.dispose();
      picture.dispose();

      return Sk18RawFrameBuffer(
        width: targetWidth,
        height: targetHeight,
        rgbaBytes: byteData!.buffer.asUint8List(),
      );
    }

    final targetWidth = authoringInLandscape
        ? spec.landscapeWidth
        : spec.portraitWidth;
    final targetHeight = authoringInLandscape
        ? spec.landscapeHeight
        : spec.portraitHeight;

    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
    );

    final isPortraitCanvas = !authoringInLandscape;
    final matchingDeviceRects = (isPortraitCanvas == rotateForPortraitDevice)
        ? rawDeviceRects
        : null;

    paintLogicalCanvas(
      canvas,
      Size(targetWidth.toDouble(), targetHeight.toDouble()),
      page: page,
      isPortrait: isPortraitCanvas,
      model: model,
      upsideDown: upsideDown,
      haEntities: haEntities,
      pressedKeyIndices: pressedKeyIndices,
      rawDeviceRects: matchingDeviceRects,
      offsetX: offsetX,
      offsetY: offsetY,
      profileName: profileName,
      statusText: statusText,
      clockString: clockString,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(targetWidth, targetHeight);
    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    image.dispose();
    picture.dispose();

    return Sk18RawFrameBuffer(
      width: targetWidth,
      height: targetHeight,
      rgbaBytes: byteData!.buffer.asUint8List(),
    );
  }
}

class Sk18CanvasPainter extends CustomPainter {
  final Sk18Page page;
  final bool isPortrait;
  final WaveshareModel model;
  final bool upsideDown;
  final Map<String, HaEntityState> haEntities;
  final Set<int> pressedKeyIndices;
  final int? selectedKeyIndex;
  final List<Sk18KeyRect>? rawDeviceRects;
  final int offsetX;
  final int offsetY;
  final String profileName;
  final String statusText;
  final String clockString;

  const Sk18CanvasPainter({
    required this.page,
    required this.isPortrait,
    this.model = WaveshareModel.sk18,
    this.upsideDown = false,
    this.haEntities = const {},
    this.pressedKeyIndices = const {},
    this.selectedKeyIndex,
    this.rawDeviceRects,
    this.offsetX = 0,
    this.offsetY = 0,
    this.profileName = 'SK18 Studio',
    this.statusText = 'SIMULATOR',
    this.clockString = '12:00',
  });

  @override
  void paint(Canvas canvas, Size size) {
    final spec = model.spec;
    final logicalWidth = isPortrait
        ? spec.portraitWidth.toDouble()
        : spec.landscapeWidth.toDouble();
    final logicalHeight = isPortrait
        ? spec.portraitHeight.toDouble()
        : spec.landscapeHeight.toDouble();

    canvas.save();
    canvas.scale(size.width / logicalWidth, size.height / logicalHeight);
    Sk18CanvasRenderer.paintLogicalCanvas(
      canvas,
      Size(logicalWidth, logicalHeight),
      page: page,
      isPortrait: isPortrait,
      model: model,
      upsideDown: upsideDown,
      haEntities: haEntities,
      pressedKeyIndices: pressedKeyIndices,
      selectedKeyIndex: selectedKeyIndex,
      rawDeviceRects: rawDeviceRects,
      offsetX: offsetX,
      offsetY: offsetY,
      profileName: profileName,
      statusText: statusText,
      clockString: clockString,
      showDesktopSelectionOutline: true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant Sk18CanvasPainter oldDelegate) {
    return oldDelegate.page != page ||
        oldDelegate.isPortrait != isPortrait ||
        oldDelegate.model != model ||
        oldDelegate.upsideDown != upsideDown ||
        oldDelegate.haEntities != haEntities ||
        oldDelegate.pressedKeyIndices != pressedKeyIndices ||
        oldDelegate.selectedKeyIndex != selectedKeyIndex ||
        oldDelegate.offsetX != offsetX ||
        oldDelegate.offsetY != offsetY ||
        oldDelegate.profileName != profileName ||
        oldDelegate.statusText != statusText ||
        oldDelegate.clockString != clockString;
  }
}
