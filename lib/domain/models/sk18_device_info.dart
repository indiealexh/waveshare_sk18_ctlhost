import 'sk18_geometry.dart';

class Sk18KeyRect {
  final int col;
  final int row;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool isKey;

  const Sk18KeyRect({
    required this.col,
    required this.row,
    required this.x,
    required this.y,
    this.width = 158,
    this.height = 158,
    this.isKey = true,
  });

  int get right => x + width - 1;
  int get bottom => y + height - 1;
  double get centerX => x + width / 2.0;
  double get centerY => y + height / 2.0;

  bool containsPoint(double px, double py) {
    return px >= x && px < (x + width) && py >= y && py < (y + height);
  }

  Sk18KeyRect copyWith({
    int? col,
    int? row,
    int? x,
    int? y,
    int? width,
    int? height,
    bool? isKey,
  }) {
    return Sk18KeyRect(
      col: col ?? this.col,
      row: row ?? this.row,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      isKey: isKey ?? this.isKey,
    );
  }

  factory Sk18KeyRect.fromJson(Map<String, dynamic> json) {
    return Sk18KeyRect(
      col: (json['col'] as num?)?.toInt() ?? 0,
      row: (json['row'] as num?)?.toInt() ?? 0,
      x: (json['x'] as num?)?.toInt() ?? 0,
      y: (json['y'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt() ?? 158,
      height: (json['height'] as num?)?.toInt() ?? 158,
      isKey: json['isKey'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'col': col,
      'row': row,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'isKey': isKey,
    };
  }
}

class Sk18DeviceInfo {
  final String deviceVersion;
  final String deviceModel;
  final int deviceWidth;
  final int deviceHeight;
  final int screenWidth;
  final int screenHeight;
  final int rectRows;
  final int rectCols;
  final List<Sk18KeyRect> rects;

  const Sk18DeviceInfo({
    required this.deviceVersion,
    required this.deviceModel,
    required this.deviceWidth,
    required this.deviceHeight,
    required this.screenWidth,
    required this.screenHeight,
    required this.rectRows,
    required this.rectCols,
    required this.rects,
  });

  bool get isPortrait => deviceHeight > deviceWidth;
  WaveshareModel get model => WaveshareModel.fromString(deviceModel);

  factory Sk18DeviceInfo.defaultPortrait() {
    final rects = <Sk18KeyRect>[];
    for (int row = 0; row < 6; row++) {
      for (int col = 0; col < 3; col++) {
        rects.add(
          Sk18KeyRect(
            col: col,
            row: row,
            x: 63 + 218 * col,
            y: 10 + 218 * row, // matches stock V2.32 raw unflipped coordinate
          ),
        );
      }
    }
    return Sk18DeviceInfo(
      deviceVersion: 'V2.32',
      deviceModel: 'SK18',
      deviceWidth: 720,
      deviceHeight: 1280,
      screenWidth: 720,
      screenHeight: 1280,
      rectRows: 6,
      rectCols: 3,
      rects: rects,
    );
  }

  factory Sk18DeviceInfo.defaultLandscape() {
    final rects = <Sk18KeyRect>[];
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 6; col++) {
        rects.add(
          Sk18KeyRect(
            col: col,
            row: row,
            x: 10 + 218 * col, // matches stock V2.32 raw unflipped coordinate
            y: 63 + 218 * row,
          ),
        );
      }
    }
    return Sk18DeviceInfo(
      deviceVersion: 'V2.32',
      deviceModel: 'SK18',
      deviceWidth: 1280,
      deviceHeight: 720,
      screenWidth: 1280,
      screenHeight: 720,
      rectRows: 3,
      rectCols: 6,
      rects: rects,
    );
  }

  /// Mirrors the stock `V2.32` `MK10` `foregroundParam` (portrait, `rotate = 1`):
  /// `304x896` panel, `5 rows x 2 cols` of `128 px` keys packed from
  /// `startX = 0, startY = 256` (no gutters), plus the `296x240` side screen
  /// at the top (`isKey = false`).
  factory Sk18DeviceInfo.defaultMk10Portrait() {
    final rects = <Sk18KeyRect>[
      const Sk18KeyRect(
        col: 0,
        row: 0,
        x: 0,
        y: 0,
        width: 296,
        height: 240,
        isKey: false,
      ),
    ];
    for (int row = 0; row < 5; row++) {
      for (int col = 0; col < 2; col++) {
        rects.add(
          Sk18KeyRect(
            col: col,
            row: row,
            x: 128 * col,
            y: 256 + 128 * row,
            width: 128,
            height: 128,
            isKey: true,
          ),
        );
      }
    }
    return Sk18DeviceInfo(
      deviceVersion: 'V2.32',
      deviceModel: 'MK10',
      deviceWidth: 304,
      deviceHeight: 896,
      screenWidth: 304,
      screenHeight: 896,
      rectRows: 5,
      rectCols: 2,
      rects: rects,
    );
  }

  /// Mirrors the stock `V2.32` `MK10` `foregroundParam` (landscape,
  /// `rotate = 0`): `896x304` panel, `2 rows x 5 cols` of `128 px` keys packed
  /// from `startX = 0, startY = 0` (no gutters), plus the `240x296` side screen
  /// at `x = 656` (`isKey = false`).
  factory Sk18DeviceInfo.defaultMk10Landscape() {
    final rects = <Sk18KeyRect>[
      const Sk18KeyRect(
        col: 0,
        row: 0,
        x: 656,
        y: 0,
        width: 240,
        height: 296,
        isKey: false,
      ),
    ];
    for (int row = 0; row < 2; row++) {
      for (int col = 0; col < 5; col++) {
        rects.add(
          Sk18KeyRect(
            col: col,
            row: row,
            x: 128 * col,
            y: 128 * row,
            width: 128,
            height: 128,
            isKey: true,
          ),
        );
      }
    }
    return Sk18DeviceInfo(
      deviceVersion: 'V2.32',
      deviceModel: 'MK10',
      deviceWidth: 896,
      deviceHeight: 304,
      screenWidth: 896,
      screenHeight: 304,
      rectRows: 2,
      rectCols: 5,
      rects: rects,
    );
  }

  factory Sk18DeviceInfo.fromGetInfoResult(Map<String, dynamic> result) {
    final panel =
        (result['devicePanel'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final rawRects = (panel['rects'] as List<dynamic>?) ?? const <dynamic>[];
    final rects = rawRects
        .whereType<Map<String, dynamic>>()
        .map(Sk18KeyRect.fromJson)
        .toList();

    final rawModel = result['deviceModel'] as String? ?? 'SK18';
    final parsedModel = WaveshareModel.fromString(rawModel);
    final spec = parsedModel.spec;

    final devWidth =
        (result['deviceWidth'] as num?)?.toInt() ?? spec.portraitWidth;
    final devHeight =
        (result['deviceHeight'] as num?)?.toInt() ?? spec.portraitHeight;
    final isPort = devHeight > devWidth;

    return Sk18DeviceInfo(
      deviceVersion: result['deviceVersion'] as String? ?? 'V2.32',
      deviceModel: parsedModel.code,
      deviceWidth: devWidth,
      deviceHeight: devHeight,
      screenWidth: (panel['screenWidth'] as num?)?.toInt() ?? devWidth,
      screenHeight: (panel['screenHeight'] as num?)?.toInt() ?? devHeight,
      rectRows:
          (panel['rectRows'] as num?)?.toInt() ??
          (isPort ? spec.portraitRows : spec.landscapeRows),
      rectCols:
          (panel['rectCols'] as num?)?.toInt() ??
          (isPort ? spec.portraitCols : spec.landscapeCols),
      rects: rects,
    );
  }

  factory Sk18DeviceInfo.fromV1ScreenMessage(Map<String, String> map) {
    final rawModel =
        map['screen_model'] ?? map['deviceModel'] ?? map['model'] ?? 'SK18';
    final parsedModel = WaveshareModel.fromString(rawModel);
    final base = parsedModel == WaveshareModel.mk10
        ? Sk18DeviceInfo.defaultMk10Portrait()
        : Sk18DeviceInfo.defaultPortrait();
    final version =
        map['version'] ?? map['deviceVersion'] ?? base.deviceVersion;
    return Sk18DeviceInfo(
      deviceVersion: version,
      deviceModel: parsedModel.code,
      deviceWidth: base.deviceWidth,
      deviceHeight: base.deviceHeight,
      screenWidth: base.screenWidth,
      screenHeight: base.screenHeight,
      rectRows: base.rectRows,
      rectCols: base.rectCols,
      rects: base.rects,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceVersion': deviceVersion,
      'deviceModel': deviceModel,
      'deviceWidth': deviceWidth,
      'deviceHeight': deviceHeight,
      'devicePanel': {
        'screenWidth': screenWidth,
        'screenHeight': screenHeight,
        'rectRows': rectRows,
        'rectCols': rectCols,
        'rects': rects.map((r) => r.toJson()).toList(),
      },
    };
  }
}
