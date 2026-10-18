
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { window } from '@kit.ArkUI';
import { preferences as dataPreferences } from '@kit.ArkData';

// 启动窗兜底色:白色。读到用户配置主题色之前的过渡色,避免非主题色的
// 蜜金闪屏(用户指定:跟随主题色失败就用白)。
const DEFAULT_PRIMARY_COLOR = 0xFFFFFFFF;

// shared_preferences 的 dart 层按类型加前缀落盘:int → 'ig<value>'。
// OHOS 插件遵循同一约定,直接 getSync 出来是 string;兼容旧 number 形式。
function parseSavedColor(raw: number | string | null | undefined): number | null {
  if (typeof raw === 'number' && raw > 0) {
    return raw;
  }
  if (typeof raw === 'string' && raw.startsWith('ig')) {
    const parsed = parseInt(raw.substring(2), 10);
    if (!Number.isNaN(parsed) && parsed > 0) {
      return parsed;
    }
  }
  return null;
}

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }

  // 启动窗背景色跟随 App 内配置的主题色:Flutter 首帧前的启动窗由
  // startWindowBackground 静态资源决定,无法表达用户配置色。这里在窗口阶段
  // 创建时读 Flutter SharedPreferences(shared_preferences_ohos 插件的存储:
  // 文件名 FlutterSharedPreferences,dart 层 key 带 flutter. 前缀)里的
  // primaryColor(ARGB int,见 theme_providers.dart 落盘逻辑),动态覆盖窗口
  // 背景色,让「启动窗→启动屏→主界面」同色一贯到底。读取失败一律回退白色,
  // 不影响启动。
  onWindowStageCreate(windowStage: window.WindowStage): void {
    super.onWindowStageCreate(windowStage)
    try {
      const prefs = dataPreferences.getPreferencesSync(this.context, {
        name: 'FlutterSharedPreferences',
      });
      const saved = parseSavedColor(
        prefs.getSync('flutter.primaryColor', '') as number | string);
      const colorValue = saved ?? DEFAULT_PRIMARY_COLOR;
      // ARGB int → '#AARRGGBB'(setWindowBackgroundColor 接受的格式)
      const colorStr = `#${(colorValue >>> 0).toString(16).padStart(8, '0')}`;
      windowStage.getMainWindow((err, win) => {
        if (err.code !== 0 || !win) {
          return;
        }
        win.setWindowBackgroundColor(colorStr);
      });
    } catch (e) {
      // 首次安装(尚未有 preferences 文件)或读取异常:保持 startWindowBackground
      // 的白色默认色,不影响启动。
    }
  }
}
