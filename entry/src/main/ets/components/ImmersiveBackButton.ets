import { curves } from '@kit.ArkUI';
import { ImmersiveTitleStyle } from '../common/ImmersiveTitleStyle';
import { FlClashColorPalette, ThemeManager } from '../common/ThemeManager';

export class BackNavigationCoordinator {
  private static handlers: Map<string, () => boolean> = new Map<string, () => boolean>();

  static register(key: string, handler: () => boolean): void {
    BackNavigationCoordinator.handlers.set(key, handler);
  }

  static unregister(key: string): void {
    BackNavigationCoordinator.handlers.delete(key);
  }

  static dispatch(key: string): boolean {
    const handler: (() => boolean) | undefined = BackNavigationCoordinator.handlers.get(key);
    if (handler) {
      return handler();
    }
    return false;
  }
}

export class ImmersivePageTransition {
  private static isReduceMotionEnabled(): boolean {
    try {
      const flag: boolean | undefined = AppStorage.get<boolean>('lexiReduceMotion');
      return flag === true;
    } catch (_err) {
      return false;
    }
  }

  static isAnimated(): boolean {
    return !ImmersivePageTransition.isReduceMotionEnabled();
  }

  static systemTransitionType(): NavigationSystemTransitionType {
    return ImmersivePageTransition.isReduceMotionEnabled()
      ? NavigationSystemTransitionType.NONE
      : NavigationSystemTransitionType.DEFAULT;
  }

  static push(stack: NavPathStack, name: string): void {
    const names: string[] = stack.getAllPathName();
    if (names.length > 0 && names[names.length - 1] === name) {
      return;
    }
    stack.pushPath(new NavPathInfo(name, undefined), {
      launchMode: LaunchMode.MOVE_TO_TOP_SINGLETON,
      animated: ImmersivePageTransition.isAnimated()
    });
  }

  static pop(stack: NavPathStack): boolean {
    if (stack.size() <= 0) {
      return false;
    }
    stack.pop(ImmersivePageTransition.isAnimated());
    return true;
  }

  static clear(stack: NavPathStack): void {
    if (stack.size() > 0) {
      stack.clear(ImmersivePageTransition.isAnimated());
    }
  }

  /** Secondary page enter/exit transitions matching LumiKit's cubic-bezier fade + horizontal slide. */
  static secondaryPage(): TransitionEffect {
    if (ImmersivePageTransition.isReduceMotionEnabled()) {
      return TransitionEffect.IDENTITY;
    }
    const curve = curves.cubicBezierCurve(0.23, 1, 0.32, 1);
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ x: 28 }))
        .animation({ duration: 220, curve: curve }),
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ x: 40 }))
        .animation({ duration: 200, curve: curve })
    );
  }

  /** Sub-mode transition matching LumiKit's FormsPage / InventoryPage modeTransition(). */
  static subMode(): TransitionEffect {
    if (ImmersivePageTransition.isReduceMotionEnabled()) {
      return TransitionEffect.IDENTITY;
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: 220, curve: curves.cubicBezierCurve(0.23, 1, 0.32, 1) }),
      TransitionEffect.IDENTITY
    );
  }

  /** Smooth fade-and-lift dismissal from Launch Screen onto Dashboard. */
  static launchOverlay(): TransitionEffect {
    if (ImmersivePageTransition.isReduceMotionEnabled()) {
      return TransitionEffect.IDENTITY;
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.IDENTITY,
      TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 1.04, y: 1.04 }))
        .animation({ duration: 240, curve: curves.cubicBezierCurve(0.23, 1, 0.32, 1) })
    );
  }
}

@Component
export struct ImmersiveBackButton {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop immersiveEnabled: boolean = true;
  onBack: () => void = (): void => {};

  build() {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(20)
        .fontColor([this.palette.onSurface])
    }
    .id('secondary-back')
    .width(38)
    .height(38)
    .padding(0)
    .backgroundColor(ImmersiveTitleStyle.background(this.palette, this.immersiveEnabled, false))
    .systemMaterial(ImmersiveTitleStyle.material(this.palette, this.immersiveEnabled, false))
    .accessibilityText('返回')
    .onClick((): void => {
      this.onBack();
    })
  }
}
