import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../domain/models/button_action.dart';
import '../../../domain/models/ha_entity_state.dart';
import '../../../domain/models/key_button_config.dart';
import '../../../domain/models/sk18_device_info.dart';
import '../../../domain/models/sk18_geometry.dart';
import '../../../domain/models/sk18_profile.dart';

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

  /// Paints the logical SK18 LCD canvas (`1280x720` in landscape or `720x1280` in portrait).
  static void paintLogicalCanvas(
    Canvas canvas,
    Size size, {
    required Sk18Page page,
    required bool isPortrait,
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

    // 2. Top & bottom non-key margin status bands (63 px height in landscape)
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

    // 3. Compute exact 18 key rectangles (with +12 px firmware margin fix + user offsets)
    final keyRects = Sk18Geometry.computeKeyRects(
      isPortrait: isPortrait,
      rawDeviceRects: rawDeviceRects,
      offsetX: offsetX,
      offsetY: offsetY,
    );

    for (int i = 0; i < keyRects.length && i < page.keys.length; i++) {
      final rectModel = keyRects[i];
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
      );
    }
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
  }) {
    final baseRect = Rect.fromLTWH(
      rectModel.x.toDouble(),
      rectModel.y.toDouble(),
      rectModel.width.toDouble(),
      rectModel.height.toDouble(),
    );

    final rrect = RRect.fromRectAndRadius(
      isPressed ? baseRect.deflate(3.0) : baseRect,
      const Radius.circular(Sk18Geometry.cornerRadius),
    );

    final accentColor = Color(keyConfig.colorHex);
    final isHaActive = haState?.isOn ?? false;

    // Keycap background gradient
    final tileFillPaint = Paint()
      ..shader = ui.Gradient.linear(
        baseRect.topLeft,
        baseRect.bottomRight,
        [
          isPressed
              ? accentColor.withValues(alpha: 0.42)
              : accentColor.withValues(alpha: isHaActive ? 0.28 : 0.16),
          const Color(0xFF1E293B),
        ],
      );
    canvas.drawRRect(rrect, tileFillPaint);

    // Active HA or Pressed glow border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (isPressed || isHaActive) ? 3.5 : Sk18Geometry.borderWidth
      ..color = isPressed
          ? Colors.white
          : (isHaActive
                ? accentColor
                : accentColor.withValues(alpha: 0.55));
    canvas.drawRRect(rrect, borderPaint);

    // Desktop studio selection ring
    if (isSelected) {
      final selectRRect = RRect.fromRectAndRadius(
        baseRect.inflate(4.0),
        const Radius.circular(Sk18Geometry.cornerRadius + 4.0),
      );
      final selectPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
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
    final pillText = _resolveTopRightPill(keyConfig, haState);
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
    final iconData = Sk18IconCatalog.resolve(keyConfig.iconName);
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: 38,
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
        baseRect.top + 42,
      ),
    );

    // Live Home Assistant telemetry bar or sub-status
    if (keyConfig.action.category == ActionCategory.homeAssistant) {
      _paintHaTelemetryOverlay(
        canvas,
        baseRect: baseRect,
        action: keyConfig.action,
        haState: haState,
        accentColor: accentColor,
      );
    }

    // Bottom Key Label
    _drawText(
      canvas,
      text: keyConfig.label,
      offset: Offset(baseRect.left + 10, baseRect.bottom - 34),
      maxWidth: baseRect.width - 20,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  static String _resolveTopRightPill(
    KeyButtonConfig keyConfig,
    HaEntityState? haState,
  ) {
    final action = keyConfig.action;
    if (action.category == ActionCategory.homeAssistant && haState != null) {
      if (action.haType == HaActionType.brightnessUp ||
          action.haType == HaActionType.brightnessDown) {
        final pct = haState.brightnessPct ?? 0;
        return '$pct%';
      }
      if (action.haType == HaActionType.hvacMode ||
          action.haType == HaActionType.hvacTempUp ||
          action.haType == HaActionType.hvacTempDown) {
        return haState.state.toUpperCase();
      }
      return haState.isOn ? 'ON' : 'OFF';
    }
    return action.summaryBadge;
  }

  static void _paintHaTelemetryOverlay(
    Canvas canvas, {
    required Rect baseRect,
    required ButtonAction action,
    required HaEntityState? haState,
    required Color accentColor,
  }) {
    if (action.haType == HaActionType.brightnessUp ||
        action.haType == HaActionType.brightnessDown) {
      final pct = (haState?.brightnessPct ?? 50).clamp(0, 100);
      final trackRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(baseRect.left + 18, baseRect.bottom - 50, baseRect.width - 36, 8),
        const Radius.circular(4),
      );
      canvas.drawRRect(trackRect, Paint()..color = const Color(0xFF0F172A));
      final fillWidth = ((baseRect.width - 36) * (pct / 100.0)).clamp(0.0, baseRect.width - 36);
      if (fillWidth > 0) {
        final fillRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(baseRect.left + 18, baseRect.bottom - 50, fillWidth, 8),
          const Radius.circular(4),
        );
        canvas.drawRRect(fillRect, Paint()..color = accentColor);
      }
      return;
    }

    if (action.haType == HaActionType.hvacMode ||
        action.haType == HaActionType.hvacTempUp ||
        action.haType == HaActionType.hvacTempDown) {
      final cur = haState?.currentTemperature;
      final target = haState?.targetTemperature;
      if (cur != null || target != null) {
        final tempLabel =
            '${cur?.toStringAsFixed(1) ?? '--'}° → ${target?.toStringAsFixed(1) ?? '--'}°';
        _drawText(
          canvas,
          text: tempLabel,
          offset: Offset(baseRect.left + 10, baseRect.bottom - 54),
          maxWidth: baseRect.width - 20,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: accentColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        );
      }
    }
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

  /// Rasterizes the SK18 canvas offscreen into raw RGBA bytes.
  ///
  /// When authoring in `1280x720` landscape (`authoringInLandscape = true`) and
  /// streaming to a portrait-scanout SK18 (`rotateForPortraitDevice = true`),
  /// this pre-rotates the `Canvas` 90° clockwise on the GPU:
  ///   `canvas.translate(720, 0); canvas.rotate(math.pi / 2);`
  /// prior to `Picture.toImage(720, 1280)`, eliminating CPU `copyRotate` overhead.
  static Future<Sk18RawFrameBuffer> renderOffscreenRgba({
    required Sk18Page page,
    required bool authoringInLandscape,
    required bool rotateForPortraitDevice,
    Map<String, HaEntityState> haEntities = const {},
    Set<int> pressedKeyIndices = const {},
    List<Sk18KeyRect>? rawDeviceRects,
    int offsetX = 0,
    int offsetY = 0,
    String profileName = 'SK18 Studio',
    String statusText = 'LIVE',
    String clockString = '12:00',
  }) async {
    final recorder = ui.PictureRecorder();

    if (authoringInLandscape && rotateForPortraitDevice) {
      const targetWidth = Sk18Geometry.portraitWidth; // 720
      const targetHeight = Sk18Geometry.portraitHeight; // 1280
      final canvas = Canvas(
        recorder,
        const Rect.fromLTWH(0, 0, 720, 1280),
      );

      // Pre-rotate on the GPU: 90 degrees clockwise
      canvas.translate(targetWidth.toDouble(), 0);
      canvas.rotate(math.pi / 2);

      paintLogicalCanvas(
        canvas,
        const Size(1280, 720),
        page: page,
        isPortrait: false,
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
        ? Sk18Geometry.landscapeWidth
        : Sk18Geometry.portraitWidth;
    final targetHeight = authoringInLandscape
        ? Sk18Geometry.landscapeHeight
        : Sk18Geometry.portraitHeight;

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
    final logicalWidth = isPortrait
        ? Sk18Geometry.portraitWidth.toDouble()
        : Sk18Geometry.landscapeWidth.toDouble();
    final logicalHeight = isPortrait
        ? Sk18Geometry.portraitHeight.toDouble()
        : Sk18Geometry.landscapeHeight.toDouble();

    canvas.save();
    canvas.scale(size.width / logicalWidth, size.height / logicalHeight);
    Sk18CanvasRenderer.paintLogicalCanvas(
      canvas,
      Size(logicalWidth, logicalHeight),
      page: page,
      isPortrait: isPortrait,
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
