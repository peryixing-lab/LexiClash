import { FlClashColorPalette, ThemeManager } from '../common/ThemeManager';
import { ImmersiveTitleStyle } from '../common/ImmersiveTitleStyle';

@Component
export struct ImmersiveTitleHeader {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop immersiveEnabled: boolean = true;
  @StorageProp('lexiTopInset') titleTopInset: number = 0;
  @StorageProp('lexiTitleButtonWidth') titleButtonWidth: number = 0;
  @BuilderParam header: () => void = this.defaultHeader;

  @Builder
  defaultHeader() {}

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.immersiveEnabled) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [
              [ImmersiveTitleStyle.scrim(this.palette), 0],
              [ImmersiveTitleStyle.scrim(this.palette), (48 + this.titleTopInset) / (64 + this.titleTopInset)],
              [Color.Transparent, 1]
            ]
          })
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no')
      }
      Row() {
        this.header()
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.titleTopInset, right: this.titleButtonWidth })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.immersiveEnabled ? Color.Transparent : this.palette.page)
    .clip(false)
  }
}

@Component
export struct ImmersiveTitlePage {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop immersiveEnabled: boolean = true;
  @Prop revisionTick: number = 0;
  @Prop scrollUnderTitle: boolean = false;
  @StorageProp('lexiTopInset') titleTopInset: number = 0;
  navPathStack: NavPathStack = new NavPathStack();
  @BuilderParam header: () => void = this.defaultSlot;
  @BuilderParam bodyContent: () => void = this.defaultSlot;
  @BuilderParam navDestinationBuilder: (name: string) => void = this.defaultNavDestination;
  onNavBarVisibilityChange: (isVisible: boolean) => void = (_isVisible: boolean): void => {};

  @Builder
  defaultSlot() {}

  @Builder
  defaultNavDestination(_name: string) {}

  @Builder
  renderNavDestination(name: string) {
    this.navDestinationBuilder(name);
  }

  @Builder
  materialTitle() {
    ImmersiveTitleHeader({
      palette: this.palette,
      immersiveEnabled: this.immersiveEnabled,
      header: (): void => { this.header(); }
    })
  }

  build() {
    WithTheme({ theme: ImmersiveTitleStyle.titleTheme(this.palette) }) {
      Navigation(this.navPathStack) {
        Column() {
          this.bodyContent()
        }
        .width('100%')
        .height('100%')
        // Main scrolls reserve this space inside the Scroll so it can scroll away.
        .padding({ top: this.scrollUnderTitle ? 0 : 64 + this.titleTopInset })
      }
      .mode(NavigationMode.Stack)
      .titleMode(NavigationTitleMode.Mini)
      .hideBackButton(true)
      .hideToolBar(true)
      .navDestination(this.renderNavDestination)
      .onNavBarStateChange((isVisible: boolean): void => {
        this.onNavBarVisibilityChange(isVisible);
      })
      .title(
        { builder: (): void => { this.materialTitle(); }, height: 64 + this.titleTopInset },
        ImmersiveTitleStyle.titleBarOptions(this.immersiveEnabled, this.scrollUnderTitle)
      )
      .width('100%')
      .height('100%')
      .background(Color.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }
}

@Component
export struct ImmersiveNavDestination {
  @Prop palette: FlClashColorPalette = ThemeManager.resolvePalette('dark', 'amber', 'vivid', false);
  @Prop immersiveEnabled: boolean = true;
  @Prop revisionTick: number = 0;
  @Prop scrollUnderTitle: boolean = false;
  @StorageProp('lexiTopInset') titleTopInset: number = 0;
  @StorageProp('lexiReduceMotion') reduceMotion: boolean = false;
  @BuilderParam header: () => void = this.defaultSlot;
  @BuilderParam bodyContent: () => void = this.defaultSlot;
  onBackRequest: () => boolean = (): boolean => false;
  onDestinationDisappear: () => void = (): void => {};

  @Builder
  defaultSlot() {}

  @Builder
  materialTitle() {
    ImmersiveTitleHeader({
      palette: this.palette,
      immersiveEnabled: this.immersiveEnabled,
      header: (): void => { this.header(); }
    })
  }

  build() {
    NavDestination() {
      WithTheme({ theme: ImmersiveTitleStyle.titleTheme(this.palette) }) {
        Column() {
          this.bodyContent()
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.scrollUnderTitle ? 0 : 64 + this.titleTopInset })
      }
    }
    .mode(NavDestinationMode.STANDARD)
    .hideBackButton(true)
    .hideToolBar(true)
    .systemTransition(this.reduceMotion ? NavigationSystemTransitionType.NONE : NavigationSystemTransitionType.DEFAULT)
    .title(
      { builder: (): void => { this.materialTitle(); }, height: 64 + this.titleTopInset },
      ImmersiveTitleStyle.titleBarOptions(this.immersiveEnabled, this.scrollUnderTitle)
    )
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.page)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => this.onBackRequest())
    .onWillDisappear((): void => {
      this.onDestinationDisappear();
    })
  }
}
