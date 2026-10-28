import '../../bridge/bridge_protocol.dart';

/// 阅读设置（shared_preferences 持久化）
class ReaderSettings {
  ReaderSettings({
    this.fontSize = 19,
    this.lineHeight = 1.7,
    this.fontFamily = 'serif', // serif | sans | custom:<fontName>
    this.fontPath, // 自定义字体文件在沙盒中的路径（FontManager 提供）
    this.themeMode = ReaderThemeMode.paper,
    this.fullRefreshEvery = 1, // 每翻 N 页做一次全刷（1=每页；0=仅局刷）
    this.margin = 32, // 页边距 px（左右原值，上下 0.6 倍）
    this.indent = 2, // 首行缩进 em（0=不缩进）
    this.paraSpacing, // 段间距 em；null=不覆盖（EPUB 自带样式说了算）
    this.showProgress = true, // 底部常驻阅读进度
  });

  double fontSize;
  double lineHeight;
  String fontFamily;
  String? fontPath;
  ReaderThemeMode themeMode;
  int fullRefreshEvery;
  double margin;
  double indent;
  double? paraSpacing;
  bool showProgress;

  /// 草稿副本：设置对话框里改的是一份拷贝，确认/即时应用时才整体写回
  ReaderSettings copy() => ReaderSettings(
        fontSize: fontSize,
        lineHeight: lineHeight,
        fontFamily: fontFamily,
        fontPath: fontPath,
        themeMode: themeMode,
        fullRefreshEvery: fullRefreshEvery,
        margin: margin,
        indent: indent,
        paraSpacing: paraSpacing,
        showProgress: showProgress,
      );

  /// 下发给引擎的排版参数（改了字段就要两边一起 +1 引擎协议号）
  Map<String, dynamic> toBridgeJson() => {
        'mode': themeMode.id,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'fontFamily': fontFamily,
        if (fontPath != null) 'fontPath': fontPath,
        'margin': margin,
        'indent': indent,
        if (paraSpacing != null) 'paraSpacing': paraSpacing,
      };

  Map<String, dynamic> toPrefsJson() => {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'fontFamily': fontFamily,
        'fontPath': fontPath,
        'themeMode': themeMode.id,
        'fullRefreshEvery': fullRefreshEvery,
        'margin': margin,
        'indent': indent,
        'paraSpacing': paraSpacing,
        'showProgress': showProgress,
      };

  factory ReaderSettings.fromPrefsJson(Map<String, dynamic> j) =>
      ReaderSettings(
        fontSize: ((j['fontSize'] ?? 19) as num).toDouble(),
        lineHeight: ((j['lineHeight'] ?? 1.7) as num).toDouble(),
        fontFamily: (j['fontFamily'] ?? 'serif') as String,
        fontPath: j['fontPath'] as String?,
        themeMode: ReaderThemeModeX.from(j['themeMode'] as String?),
        fullRefreshEvery: (j['fullRefreshEvery'] ?? 1) as int,
        margin: ((j['margin'] ?? 32) as num).toDouble(),
        indent: ((j['indent'] ?? 2) as num).toDouble(),
        paraSpacing: (j['paraSpacing'] as num?)?.toDouble(),
        showProgress: (j['showProgress'] ?? true) as bool,
      );
}
