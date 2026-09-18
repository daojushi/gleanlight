import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppFontChoice {
  const AppFontChoice(this.id, this.label, this.family);
  final String id;
  final String label;
  final String? family;
}

class AppearanceSettings extends ChangeNotifier {
  AppearanceSettings._(this._preferences, this.selectedId, this.fontFamily);

  static const choices = [
    AppFontChoice('system', '系统默认', null),
    AppFontChoice('yahei', '微软雅黑', 'Microsoft YaHei UI'),
    AppFontChoice('dengxian', '等线', 'DengXian'),
    AppFontChoice('simsun', '宋体', 'SimSun'),
  ];

  static const _choiceKey = 'appearance.fontChoice';
  static const _customPathKey = 'appearance.customFontPath';
  static const _customFamily = 'ItsImportedFont';

  final SharedPreferences _preferences;
  String selectedId;
  String? fontFamily;
  String? customFontPath;

  static Future<AppearanceSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final selected = preferences.getString(_choiceKey) ?? 'system';
    final customPath = preferences.getString(_customPathKey);
    String? family = choices
        .where((choice) => choice.id == selected)
        .firstOrNull
        ?.family;
    if (selected == 'custom' && customPath != null) {
      try {
        await _loadFont(customPath);
        family = _customFamily;
      } catch (_) {
        family = null;
      }
    }
    return AppearanceSettings._(preferences, selected, family)
      ..customFontPath = customPath;
  }

  Future<void> select(String id) async {
    final choice = choices.where((item) => item.id == id).firstOrNull;
    if (choice == null) return;
    selectedId = choice.id;
    fontFamily = choice.family;
    await _preferences.setString(_choiceKey, choice.id);
    notifyListeners();
  }

  Future<void> importFont(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) throw StateError('字体文件不存在');
    final extension = p.extension(source.path).toLowerCase();
    if (extension != '.ttf' && extension != '.otf') {
      throw ArgumentError('仅支持 TTF 或 OTF 字体');
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'fonts'));
    await directory.create(recursive: true);
    final target = p.join(directory.path, 'user-font$extension');
    await source.copy(target);
    await _loadFont(target);
    customFontPath = target;
    selectedId = 'custom';
    fontFamily = _customFamily;
    await _preferences.setString(_customPathKey, target);
    await _preferences.setString(_choiceKey, selectedId);
    notifyListeners();
  }

  static Future<void> _loadFont(String path) async {
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(_customFamily);
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}
