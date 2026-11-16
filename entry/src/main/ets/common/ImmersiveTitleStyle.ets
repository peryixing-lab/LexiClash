import { uiMaterial } from '@kit.ArkUI';
import { FlClashColorPalette } from './ThemeManager';

// Like LexiNote's title chips, keep native material on the controls themselves.
// Navigation supplies the gradual blur behind the transparent title container.
export class ImmersiveTitleStyle {
  private static supported: boolean | undefined = undefined;
  private static materials: Map<string, uiMaterial.ImmersiveMaterial> =
    new Map<string, uiMaterial.ImmersiveMaterial>();

  static isSupported(): boolean {
    if (ImmersiveTitleStyle.supported === undefined) {
      try {
        ImmersiveTitleStyle.supported = uiMaterial.isImmersiveMaterialSupported();
      } catch (error) {
        ImmersiveTitleStyle.supported = false;
      }
    }
    return ImmersiveTitleStyle.supported;
  }

  static background(palette: FlClashColorPalette, enabled: boolean, active: boolean = false): ResourceColor {
    if (enabled && ImmersiveTitleStyle.isSupported()) {
      return Color.Transparent;
    }
    return active ? palette.primarySoft : palette.card;
  }

  static material(palette: FlClashColorPalette, enabled: boolean, active: boolean = false): uiMaterial.Material {
    if (!enabled || !ImmersiveTitleStyle.isSupported()) {
      return uiMaterial.Material.empty;
    }
    const tint: string = (palette.isDark ? '#CC' : '#38') +
      (active ? palette.primary : palette.card).substring(1);
    const cacheKey: string = `${tint}_${palette.primary}`;
    const cached: uiMaterial.ImmersiveMaterial | undefined = ImmersiveTitleStyle.materials.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    const material: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: tint,
      interactive: true,
      applyShadow: true,
      lightEffect: { color: palette.primary }
    });
    ImmersiveTitleStyle.materials.set(cacheKey, material);
    return material;
  }

  static scrim(palette: FlClashColorPalette): string {
    return (palette.isDark ? '#E6' : '#00') + palette.page.substring(1);
  }
}
