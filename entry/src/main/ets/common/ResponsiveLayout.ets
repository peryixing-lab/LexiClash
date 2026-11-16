// ResponsiveLayout.ets — Adaptive breakpoints & layout metrics for Phone, Tablet, and 2in1 PC

export class ResponsiveLayout {
  static readonly COMPACT_MAX_VP: number = 600;
  static readonly EXPANDED_MIN_VP: number = 840;
  static readonly WIDE_MIN_VP: number = 1080;

  static isCompact(widthVp: number): boolean {
    return widthVp < ResponsiveLayout.COMPACT_MAX_VP;
  }

  static isMedium(widthVp: number): boolean {
    return widthVp >= ResponsiveLayout.COMPACT_MAX_VP && widthVp < ResponsiveLayout.EXPANDED_MIN_VP;
  }

  static isExpanded(widthVp: number): boolean {
    return widthVp >= ResponsiveLayout.EXPANDED_MIN_VP;
  }

  static dashboardColumns(widthVp: number): number {
    if (widthVp >= ResponsiveLayout.WIDE_MIN_VP) {
      return 3;
    }
    if (widthVp >= ResponsiveLayout.COMPACT_MAX_VP) {
      return 2;
    }
    return 1;
  }

  static proxyColumnsTemplate(widthVp: number): string {
    if (widthVp >= ResponsiveLayout.WIDE_MIN_VP) {
      return '1fr 1fr 1fr 1fr';
    }
    if (widthVp >= ResponsiveLayout.COMPACT_MAX_VP) {
      return '1fr 1fr 1fr';
    }
    return '1fr 1fr';
  }

  static profilesColumnsTemplate(widthVp: number): string {
    if (widthVp >= 720) {
      return '1fr 1fr';
    }
    return '1fr';
  }

  static seedGridColumnsTemplate(widthVp: number): string {
    if (widthVp >= ResponsiveLayout.COMPACT_MAX_VP) {
      return '1fr 1fr 1fr';
    }
    return '1fr 1fr';
  }

  static contentMaxWidth(widthVp: number): number {
    if (widthVp >= ResponsiveLayout.WIDE_MIN_VP) {
      return 1040;
    }
    if (widthVp >= ResponsiveLayout.EXPANDED_MIN_VP) {
      return 880;
    }
    if (widthVp >= ResponsiveLayout.COMPACT_MAX_VP) {
      return 740;
    }
    return Math.max(320, widthVp);
  }

  static readingMaxWidth(widthVp: number): number {
    if (widthVp >= ResponsiveLayout.COMPACT_MAX_VP) {
      return 760;
    }
    return Math.max(320, widthVp);
  }

  static sheetMaxWidth(widthVp: number): number {
    if (widthVp >= ResponsiveLayout.COMPACT_MAX_VP) {
      return 520;
    }
    return Math.max(320, widthVp);
  }

  static horizontalPadding(widthVp: number): number {
    if (widthVp >= ResponsiveLayout.EXPANDED_MIN_VP) {
      return 24;
    }
    if (widthVp >= ResponsiveLayout.COMPACT_MAX_VP) {
      return 20;
    }
    return 16;
  }

  static bottomContentPadding(widthVp: number, bottomInset: number): number {
    // Expanded screens use left navigation rail instead of bottom dock.
    return ResponsiveLayout.isExpanded(widthVp) ? 28 + bottomInset : 104 + bottomInset;
  }

  static secondaryBottomPadding(bottomInset: number): number {
    return 28 + bottomInset;
  }

  static floatingBarWidth(widthVp: number, navBarStyle: string): number {
    const margin: number = navBarStyle === 'floating' ? 32 : 0;
    if (widthVp >= ResponsiveLayout.COMPACT_MAX_VP) {
      return Math.min(480, Math.max(220, widthVp - margin));
    }
    return Math.max(180, widthVp - margin);
  }
}
