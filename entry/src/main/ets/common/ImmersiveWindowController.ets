import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemeModeKind } from '../core/CoreProtocol';

export class ImmersiveWindowController {
  private static mainWindow: window.Window | null = null;
  private static abilityContext: common.UIAbilityContext | null = null;
  private static originalBars: window.SystemBarProperties | null = null;
  private static lastThemeKey: string = '';
  private static avoidListening: boolean = false;
  private static sizeListening: boolean = false;
  private static titleBtnListening: boolean = false;
  private static avoidListener: (options: window.AvoidAreaOptions) => void =
    (options: window.AvoidAreaOptions): void => {
      if (options.type !== window.AvoidAreaType.TYPE_KEYBOARD) {
        ImmersiveWindowController.updateInsets();
      }
    };
  private static sizeListener: (size: window.Size) => void = (_size: window.Size): void => {
    ImmersiveWindowController.updateInsets();
  };
  private static titleBtnListener: (rect: window.TitleButtonRect) => void = (rect: window.TitleButtonRect): void => {
    ImmersiveWindowController.updateTitleButtonWidth(rect);
  };

  static attach(mainWindow: window.Window, context: common.UIAbilityContext): void {
    ImmersiveWindowController.mainWindow = mainWindow;
    ImmersiveWindowController.abilityContext = context;
    ImmersiveWindowController.lastThemeKey = '';
    try {
      ImmersiveWindowController.originalBars = mainWindow.getWindowSystemBarProperties();
    } catch (error) {
      hilog.info(0x3200, 'LexiImmersive', 'Could not read initial system bar properties.');
    }
    AppStorage.setOrCreate<number>('lexiTitleButtonWidth', 0);
    try {
      const btnRect: window.TitleButtonRect = mainWindow.getTitleButtonRect();
      ImmersiveWindowController.updateTitleButtonWidth(btnRect);
    } catch (_btnErr) {
      // Non-2in1/phone windows may not expose title button rect.
    }
    ImmersiveWindowController.updateInsets();
    try {
      mainWindow.on('avoidAreaChange', ImmersiveWindowController.avoidListener);
      ImmersiveWindowController.avoidListening = true;
    } catch (error) {
      hilog.info(0x3200, 'LexiImmersive', 'Avoid-area monitoring unavailable.');
    }
    try {
      mainWindow.on('windowSizeChange', ImmersiveWindowController.sizeListener);
      ImmersiveWindowController.sizeListening = true;
    } catch (error) {
      hilog.info(0x3200, 'LexiImmersive', 'Window-size monitoring unavailable.');
    }
    try {
      mainWindow.on('windowTitleButtonRectChange', ImmersiveWindowController.titleBtnListener);
      ImmersiveWindowController.titleBtnListening = true;
    } catch (_titleErr) {
      ImmersiveWindowController.titleBtnListening = false;
    }
    AppStorage.setOrCreate<boolean>('lexiWindowReady', true);
  }

  private static updateTitleButtonWidth(rect: window.TitleButtonRect): void {
    const mainWindow: window.Window | null = ImmersiveWindowController.mainWindow;
    if (mainWindow === null || rect === undefined || rect === null) {
      return;
    }
    try {
      const uiContext = mainWindow.getUIContext();
      const rawWidth: number = Math.max(0, Number(rect.width ?? 0) + Number(rect.right ?? 0));
      AppStorage.setOrCreate<number>('lexiTitleButtonWidth', rawWidth > 0 ? uiContext.px2vp(rawWidth) : 0);
    } catch (_err) {
      // ignore
    }
  }

  private static updateInsets(): void {
    const mainWindow: window.Window | null = ImmersiveWindowController.mainWindow;
    if (mainWindow === null) return;
    try {
      const system: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutout: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const indicator: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const props: window.WindowProperties = mainWindow.getWindowProperties();
      const windowHeight: number = props.windowRect.height;
      const windowWidth: number = props.windowRect.width;
      const top: number = Math.max(system.topRect.height > 0 ? system.topRect.top + system.topRect.height : 0,
        cutout.topRect.height > 0 ? cutout.topRect.top + cutout.topRect.height : 0);
      const bottom: number = Math.max(
        system.bottomRect.height > 0 ? windowHeight - system.bottomRect.top : 0,
        cutout.bottomRect.height > 0 ? windowHeight - cutout.bottomRect.top : 0,
        indicator.bottomRect.height > 0 ? windowHeight - indicator.bottomRect.top : 0);
      const uiContext = mainWindow.getUIContext();
      AppStorage.setOrCreate<number>('lexiTopInset', uiContext.px2vp(Math.max(0, top)));
      AppStorage.setOrCreate<number>('lexiBottomInset', uiContext.px2vp(Math.max(0, bottom)));
      if (windowWidth > 0) {
        AppStorage.setOrCreate<number>('lexiWindowWidthVp', uiContext.px2vp(windowWidth));
      }
    } catch (error) {
      hilog.warn(0x3200, 'LexiImmersive', 'Could not refresh system and cutout insets.');
    }
  }

  static applyTheme(mode: ThemeModeKind, isDark: boolean, pageColor: string): void {
    const mainWindow: window.Window | null = ImmersiveWindowController.mainWindow;
    const context: common.UIAbilityContext | null = ImmersiveWindowController.abilityContext;
    if (mainWindow === null || context === null) {
      return;
    }
    const themeKey: string = `${mode}_${isDark}_${pageColor}`;
    if (ImmersiveWindowController.lastThemeKey === themeKey) {
      return;
    }
    ImmersiveWindowController.lastThemeKey = themeKey;
    try {
      context.getApplicationContext().setColorMode(mode === 'auto'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
        : (isDark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT));
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: isDark ? '#FFFFFFFF' : '#FF1C1C1E',
        navigationBarContentColor: isDark ? '#FFFFFFFF' : '#FF1C1C1E',
        enableStatusBarAnimation: false,
        enableNavigationBarAnimation: false
      }).catch((): void => {
        ImmersiveWindowController.lastThemeKey = '';
        hilog.warn(0x3200, 'LexiImmersive', 'System bar appearance could not be updated.');
      });
    } catch (error) {
      ImmersiveWindowController.lastThemeKey = '';
    }
  }

  static detach(): void {
    const mainWindow: window.Window | null = ImmersiveWindowController.mainWindow;
    if (mainWindow !== null) {
      if (ImmersiveWindowController.avoidListening) {
        try {
          mainWindow.off('avoidAreaChange', ImmersiveWindowController.avoidListener);
        } catch (error) {
          hilog.info(0x3200, 'LexiImmersive', 'Avoid-area listener already released.');
        }
      }
      if (ImmersiveWindowController.sizeListening) {
        try {
          mainWindow.off('windowSizeChange', ImmersiveWindowController.sizeListener);
        } catch (error) {
          hilog.info(0x3200, 'LexiImmersive', 'Window-size listener already released.');
        }
      }
      if (ImmersiveWindowController.titleBtnListening) {
        try {
          mainWindow.off('windowTitleButtonRectChange', ImmersiveWindowController.titleBtnListener);
        } catch (error) {
          hilog.info(0x3200, 'LexiImmersive', 'Title-button listener already released.');
        }
      }
      try {
        const bars: window.SystemBarProperties | null = ImmersiveWindowController.originalBars;
        if (bars !== null) {
          mainWindow.setWindowSystemBarProperties(bars).catch((): void => {});
        }
      } catch (error) {
        hilog.info(0x3200, 'LexiImmersive', 'Window already released during immersion cleanup.');
      }
    }
    try {
      ImmersiveWindowController.abilityContext?.getApplicationContext()
        .setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (error) {
      // ignore
    }
    AppStorage.setOrCreate<boolean>('lexiWindowReady', false);
    ImmersiveWindowController.mainWindow = null;
    ImmersiveWindowController.abilityContext = null;
    ImmersiveWindowController.originalBars = null;
    ImmersiveWindowController.avoidListening = false;
    ImmersiveWindowController.sizeListening = false;
    ImmersiveWindowController.titleBtnListening = false;
    AppStorage.setOrCreate<number>('lexiTitleButtonWidth', 0);
  }
}
