import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x1005;
const TAG = 'LB_THEME';

/**
 * 设计 token —— 数值全部对齐设计稿 lightbearing_ui.html。
 *
 * 颜色统一走资源（resources/base|dark/element/color.json），由系统深浅色驱动；
 * 需要在 Canvas 里使用的场合，用 ThemeColors.load() 从资源管理器取真实色值。
 */
export class Spacing {
  static readonly XS: number = 4;
  static readonly S: number = 8;
  static readonly M: number = 12;
  static readonly L: number = 16;
  static readonly XL: number = 20;
  static readonly XXL: number = 24;
  static readonly XXXL: number = 32;
}

/** 设计稿：.card 19 / .hero 24 / 按钮 chip 12 / .chip 40 / .stat 15 / .appicon 17 */
export class Radius {
  static readonly CARD: number = 19;
  static readonly HERO: number = 24;
  static readonly BUTTON: number = 12;
  static readonly CHIP: number = 40;
  static readonly STAT: number = 15;
  static readonly ICONBOX: number = 12;
  static readonly APPLOGO: number = 17;
}

/** 设计稿字级：.eyebrow 12 / .subtitle 14 / .card h3 14 / .small 12 / .stat b 24 / .pagetitle 29-42
 *  正文按任务书 §3「正文 14–16vp」取 14，卡片标题/副标题 15 形成层级。 */
export class FontSize {
  static readonly EYEBROW: number = 12;
  static readonly CAPTION: number = 11;
  static readonly SMALL: number = 12;
  static readonly BODY: number = 14;
  static readonly BODY_L: number = 15;
  static readonly TITLE: number = 20;
  static readonly H1: number = 30;
  static readonly HERO_H2: number = 22;
  static readonly STAT: number = 24;
  static readonly NAV: number = 13;
}

/** 设计稿 .navcaption / .caps：10px 大写 字距 2 */
export const NAV_CAPTION_SIZE: number = 10;
export const NAV_CAPTION_SPACING: number = 2;
/** 设计稿 .eyebrow 字距 1.1 */
export const EYEBROW_SPACING: number = 1.1;

/** 触控热区下限 */
export const MIN_TOUCH: number = 44;

/** Canvas 用的具体色值（从资源解析，随深浅色变化） */
export class ThemeColors {
  bg: string = '#0D1A29';
  panel: string = '#182C3D';
  panel2: string = '#213B4E';
  primary: string = '#FFBC6B';
  accent: string = '#73D9D5';
  ink: string = '#F9FAF3';
  muted: string = '#A2B9C5';
  line: string = '#2C4759';

  static load(context: common.Context): ThemeColors {
    const c = new ThemeColors();
    const manager = context.resourceManager;
    c.bg = ThemeColors.hex(manager, $r('app.color.lb_bg').id, c.bg);
    c.panel = ThemeColors.hex(manager, $r('app.color.lb_panel').id, c.panel);
    c.panel2 = ThemeColors.hex(manager, $r('app.color.lb_panel2').id, c.panel2);
    c.primary = ThemeColors.hex(manager, $r('app.color.lb_primary').id, c.primary);
    c.accent = ThemeColors.hex(manager, $r('app.color.lb_accent').id, c.accent);
    c.ink = ThemeColors.hex(manager, $r('app.color.lb_ink').id, c.ink);
    c.muted = ThemeColors.hex(manager, $r('app.color.lb_muted').id, c.muted);
    c.line = ThemeColors.hex(manager, $r('app.color.lb_line').id, c.line);
    return c;
  }

  private static hex(manager: resourceManager.ResourceManager, resId: number, fallback: string): string {
    try {
      const value = manager.getColorSync(resId);
      return ThemeColors.toHex(value);
    } catch (err) {
      return fallback;
    }
  }

  /** ARGB 整数 → #RRGGBB（Canvas 不支持独立 alpha 通道） */
  static toHex(argb: number): string {
    const r = (argb >> 16) & 0xFF;
    const g = (argb >> 8) & 0xFF;
    const b = argb & 0xFF;
    return `#${ThemeColors.pad(r)}${ThemeColors.pad(g)}${ThemeColors.pad(b)}`;
  }

  private static pad(v: number): string {
    const s = v.toString(16);
    return s.length === 1 ? `0${s}` : s;
  }
}

/** 主题应用与读取 */
export class Theme {
  /** 0=跟随系统 1=深色 2=浅色 */
  static apply(context: common.Context, mode: number): void {
    try {
      let target = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (mode === 1) {
        target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      } else if (mode === 2) {
        target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      }
      context.getApplicationContext().setColorMode(target);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'setColorMode failed %{public}s', JSON.stringify(e));
    }
  }

  static isDark(context: common.Context): boolean {
    try {
      const configuration = context.getApplicationContext().resourceManager.getConfigurationSync();
      return configuration.colorMode === resourceManager.ColorMode.DARK;
    } catch (err) {
      return true;
    }
  }
}

/** 光线阶段 → 展示颜色资源 */
export class PhaseColor {
  static of(phase: number): Resource {
    if (phase === 5) {
      return $r('app.color.lb_primary');
    }
    if (phase === 4) {
      return $r('app.color.lb_accent');
    }
    return $r('app.color.lb_muted');
  }
}
