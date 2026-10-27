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
  });

  double fontSize;
  double lineHeight;
  String fontFamily;
  String? fontPath;
  ReaderThemeMode themeMode;
  int fullRefreshEvery;

  Map<String, dynamic> toBridgeJson() => {
        'mode': themeMode.id,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'fontFamily': fontFamily,
        if (fontPath != null) 'fontPath': fontPath,
      };

  Map<String, dynamic> toPrefsJson() => {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'fontFamily': fontFamily,
        'fontPath': fontPath,
        'themeMode': themeMode.id,
        'fullRefreshEvery': fullRefreshEvery,
      };

  factory ReaderSettings.fromPrefsJson(Map<String, dynamic> j) =>
      ReaderSettings(
        fontSize: ((j['fontSize'] ?? 19) as num).toDouble(),
        lineHeight: ((j['lineHeight'] ?? 1.7) as num).toDouble(),
        fontFamily: (j['fontFamily'] ?? 'serif') as String,
        fontPath: j['fontPath'] as String?,
        themeMode: ReaderThemeModeX.from(j['themeMode'] as String?),
        fullRefreshEvery: (j['fullRefreshEvery'] ?? 1) as int,
      );
}
