import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import {
  FontSize, Radius, Spacing, MIN_TOUCH, NAV_CAPTION_SIZE, NAV_CAPTION_SPACING, Theme
} from '../common/Theme';
import { AppDb } from '../repository/AppDb';
import { Dialogs } from '../components/Widgets';
import { HomePage } from './HomePage';
import { SunPathPage } from './SunPathPage';
import { ReversePage } from './ReversePage';
import { LocationsPage } from './LocationsPage';
import { CompassPage } from './CompassPage';
import { MapPage } from './MapPage';
import { PlannerPage } from './PlannerPage';
import { CalendarPage } from './CalendarPage';
import { ComparePage } from './ComparePage';
import { SettingsPage } from './SettingsPage';

/** 一级导航项：图标按状态取不同色变体（与设计稿 .navbtn 的 muted/ink 一致） */
class NavItem {
  route: string = '';
  label: string = '';
  iconMuted: Resource = $r('app.media.ic_home_muted');
  iconInk: Resource = $r('app.media.ic_home_ink');
  iconPrimary: Resource = $r('app.media.ic_home_primary');

  static of(route: string, label: string, muted: Resource, ink: Resource, primary: Resource): NavItem {
    const n = new NavItem();
    n.route = route;
    n.label = label;
    n.iconMuted = muted;
    n.iconInk = ink;
    n.iconPrimary = primary;
    return n;
  }
}

/**
 * 应用外壳：Navigation + NavDestination。
 *
 * 视觉对齐设计稿：左侧 .sidebar（品牌区 + PAGES 小标题 + .navbtn 高亮）/
 * 手机 .mobiletabs 底部导航；页面背景带主色径向光晕。
 */
@Entry
@Component
struct Index {
  private pathStack: NavPathStack = new NavPathStack();
  @State currentRoute: string = 'home';
  @State isTablet: boolean = false;
  @State ready: boolean = false;
  @State bootError: string = '';
  @State showOnboarding: boolean = false;
  /** 回到首页时递增，通知 HomePage 重新读取本地数据 */
  @State homeToken: number = 0;

  private primaryItems: NavItem[] = [
    NavItem.of('home', '今日', $r('app.media.ic_home_muted'), $r('app.media.ic_home_ink'),
      $r('app.media.ic_home_primary')),
    NavItem.of('sunpath', '轨迹', $r('app.media.ic_sunpath_muted'), $r('app.media.ic_sunpath_ink'),
      $r('app.media.ic_sunpath_primary')),
    NavItem.of('planner', '计划', $r('app.media.ic_planner_muted'), $r('app.media.ic_planner_ink'),
      $r('app.media.ic_planner_primary')),
    NavItem.of('settings', '设置', $r('app.media.ic_settings_muted'), $r('app.media.ic_settings_ink'),
      $r('app.media.ic_settings_primary'))
  ];

  private allItems: NavItem[] = [
    NavItem.of('home', '今日光线', $r('app.media.ic_home_muted'), $r('app.media.ic_home_ink'),
      $r('app.media.ic_home_primary')),
    NavItem.of('sunpath', '太阳轨迹', $r('app.media.ic_sunpath_muted'), $r('app.media.ic_sunpath_ink'),
      $r('app.media.ic_sunpath_primary')),
    NavItem.of('reverse', '反向寻光', $r('app.media.ic_reverse_muted'), $r('app.media.ic_reverse_ink'),
      $r('app.media.ic_reverse_primary')),
    NavItem.of('locations', '机位库', $r('app.media.ic_locations_muted'), $r('app.media.ic_locations_ink'),
      $r('app.media.ic_locations_primary')),
    NavItem.of('compass', '现场罗盘', $r('app.media.ic_compass_muted'), $r('app.media.ic_compass_ink'),
      $r('app.media.ic_compass_primary')),
    NavItem.of('map', '地图方位', $r('app.media.ic_map_muted'), $r('app.media.ic_map_ink'),
      $r('app.media.ic_map_primary')),
    NavItem.of('planner', '拍摄计划', $r('app.media.ic_planner_muted'), $r('app.media.ic_planner_ink'),
      $r('app.media.ic_planner_primary')),
    NavItem.of('calendar', '日历', $r('app.media.ic_calendar_muted'), $r('app.media.ic_calendar_ink'),
      $r('app.media.ic_calendar_primary')),
    NavItem.of('compare', '时间比较', $r('app.media.ic_compare_muted'), $r('app.media.ic_compare_ink'),
      $r('app.media.ic_compare_primary')),
    NavItem.of('settings', '设置', $r('app.media.ic_settings_muted'), $r('app.media.ic_settings_ink'),
      $r('app.media.ic_settings_primary'))
  ];

  aboutToAppear(): void {
    this.bootstrap();
  }

  private hostContext(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private async bootstrap(): Promise<void> {
    try {
      const ctx = this.hostContext();
      await AppState.bootstrap(ctx);
      Theme.apply(ctx, AppState.settings.themeMode);
      this.showOnboarding = AppState.settings.onboarded === 0;
      this.ready = true;
    } catch (err) {
      this.bootError = `启动失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private async finishOnboarding(): Promise<void> {
    this.showOnboarding = false;
    try {
      AppState.settings.onboarded = 1;
      // 只落 onboarded，避免把内存里的默认 themeMode 一并固化
      await AppDb.saveSetting('onboarded', '1');
    } catch (err) {
      // 引导状态写入失败不阻塞使用
    }
  }

  /** 一级路由：底部导航/侧栏直达，切换时不应播放「返回+推入」两段转场 */
  private isTabRoute(route: string): boolean {
    return route === 'sunpath' || route === 'planner' || route === 'settings' || route === 'more';
  }

  /** 统一导航入口：有未保存编辑时先明确确认，再真正跳转 */
  private go(route: string): void {
    if (AppState.dirtyForm.length > 0 && route !== this.currentRoute) {
      const label = AppState.dirtyForm;
      Dialogs.confirm(this.getUIContext(), '放弃未保存的编辑？',
        `${label}还没有保存，离开将丢弃本次输入。`, '放弃并离开', () => {
          AppState.clearDirty();
          this.navigateTo(route);
        });
      return;
    }
    this.navigateTo(route);
  }

  private navigateTo(route: string): void {
    if (route === 'home') {
      // 回到内容区：关闭动画，避免先倒退再前进的抖动
      this.pathStack.clear(false);
      this.currentRoute = 'home';
      this.homeToken = this.homeToken + 1;
      return;
    }
    if (this.currentRoute === route && this.pathStack.size() > 0) {
      return;
    }
    if (this.isTabRoute(route)) {
      // 一级切换：原地替换，无动画
      if (this.pathStack.size() === 0) {
        this.pathStack.pushPathByName(route, '', false);
      } else {
        this.pathStack.replacePathByName(route, '', false);
      }
      this.currentRoute = route;
      return;
    }
    // 二级页面：先无动画回到内容区，再播放一次正常的推入转场
    this.pathStack.clear(false);
    this.pathStack.pushPathByName(route, '', true);
    this.currentRoute = route;
  }

  private back(): void {
    if (this.pathStack.size() > 0) {
      this.pathStack.pop(true);
    }
    this.currentRoute = 'home';
  }

  @Builder
  destinationBuilder(name: string) {
    NavDestination() {
      if (name === 'sunpath') {
        SunPathPage({
          onNavigate: (route: string) => {
            this.go(route);
          },
          onBack: () => {
            this.back();
          }
        })
      } else if (name === 'reverse') {
        ReversePage({
          onNavigate: (route: string) => {
            this.go(route);
          },
          onBack: () => {
            this.back();
          }
        })
      } else if (name === 'locations') {
        LocationsPage({
          onNavigate: (route: string) => {
            this.go(route);
          },
          onBack: () => {
            this.back();
          }
        })
      } else if (name === 'compass') {
        CompassPage({
          onNavigate: (route: string) => {
            this.go(route);
          },
          onBack: () => {
            this.back();
          }
        })
      } else if (name === 'map') {
        MapPage({
          onNavigate: (route: string) => {
            this.go(route);
          },
          onBack: () => {
            this.back();
          }
        })
      } else if (name === 'planner') {
        PlannerPage({
          onNavigate: (route: string) => {
            this.go(route);
          },
          onBack: () => {
            this.back();
          }
        })
      } else if (name === 'calendar') {
        CalendarPage({
          onNavigate: (route: string) => {
            this.go(route);
          },
          onBack: () => {
            this.back();
          }
        })
      } else if (name === 'compare') {
        ComparePage({
          onNavigate: (route: string) => {
            this.go(route);
          },
          onBack: () => {
            this.back();
          }
        })
      } else if (name === 'settings') {
        SettingsPage({
          onNavigate: (route: string) => {
            this.go(route);
          },
          onBack: () => {
            this.back();
          }
        })
      } else {
        this.morePage()
      }
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.lb_bg'))
    .onBackPressed(() => {
      // 有未保存的表单编辑时明确提示，而不是静默丢弃
      if (AppState.dirtyForm.length > 0) {
        const label = AppState.dirtyForm;
        Dialogs.confirm(this.getUIContext(), '放弃未保存的编辑？',
          `${label}还没有保存，返回将丢弃本次输入。`, '放弃并返回', () => {
            AppState.clearDirty();
            this.back();
          });
        return true;
      }
      return false;
    })
  }

  @Builder
  morePage() {
    Scroll() {
      Column({ space: Spacing.L }) {
        Column({ space: Spacing.S }) {
          Text('LIGHTBEARING · MORE')
            .fontSize(FontSize.EYEBROW)
            .fontWeight(FontWeight.Bold)
            .letterSpacing(1.1)
            .fontColor($r('app.color.lb_primary'))
          Text('更多工具')
            .fontSize(FontSize.H1)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.lb_ink'))
          Text('逐光的全部页面都可以从这里直达。')
            .fontSize(FontSize.BODY_L)
            .fontColor($r('app.color.lb_muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Grid() {
          ForEach(this.allItems, (item: NavItem) => {
            GridItem() {
              Column({ space: Spacing.M }) {
                Stack({ alignContent: Alignment.Center }) {
                  Image(item.iconPrimary)
                    .width(22)
                    .height(22)
                    .objectFit(ImageFit.Contain)
                }
                .width(44)
                .height(44)
                .backgroundColor($r('app.color.lb_iconbox_bg'))
                .borderRadius(Radius.ICONBOX)

                Text(item.label)
                  .fontSize(FontSize.BODY)
                  .fontColor($r('app.color.lb_ink'))
              }
              .width('100%')
              .height(112)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.lb_panel'))
              .borderRadius(Radius.CARD)
              .borderWidth(1)
              .borderColor($r('app.color.lb_line'))
              .onClick(() => {
                this.go(item.route);
              })
            }
          }, (item: NavItem) => `more_${item.route}`)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(Spacing.M)
        .rowsGap(Spacing.M)
        .width('100%')
        .height(484)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .padding(Spacing.XL)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.lb_bg'))
  }

  /** 手机底部导航（对应 .mobiletabs） */
  @Builder
  bottomBar() {
    Row() {
      ForEach(this.primaryItems, (item: NavItem) => {
        Column({ space: 3 }) {
          Image(this.currentRoute === item.route ? item.iconPrimary : item.iconMuted)
            .width(20)
            .height(20)
            .objectFit(ImageFit.Contain)
          Text(item.label)
            .fontSize(FontSize.CAPTION)
            .fontColor(this.currentRoute === item.route
              ? $r('app.color.lb_primary') : $r('app.color.lb_muted'))
        }
        .layoutWeight(1)
        .height(58)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.go(item.route);
        })
        .accessibilityText(item.label)
      }, (item: NavItem) => `bar_${item.route}`)

      Column({ space: 3 }) {
        Image(this.currentRoute === 'more'
          ? $r('app.media.ic_more_primary') : $r('app.media.ic_more_muted'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
        Text('更多')
          .fontSize(FontSize.CAPTION)
          .fontColor(this.currentRoute === 'more'
            ? $r('app.color.lb_primary') : $r('app.color.lb_muted'))
      }
      .layoutWeight(1)
      .height(58)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.go('more');
      })
      .accessibilityText('更多工具')
    }
    .width('100%')
    .backgroundColor($r('app.color.lb_panel'))
    .border({ width: { top: 1 }, color: $r('app.color.lb_line') })
  }

  /** 平板左侧导航（对应 .sidebar：品牌区 + PAGES 小标题 + navbtn） */
  @Builder
  rail() {
    Column({ space: 2 }) {
      // 品牌区
      Row({ space: Spacing.M }) {
        Stack({ alignContent: Alignment.Center }) {
          Image($r('app.media.ic_sun_bg'))
            .width(30)
            .height(30)
            .objectFit(ImageFit.Contain)
        }
        .width(48)
        .height(48)
        .borderRadius(Radius.APPLOGO)
        .linearGradient({
          angle: 130,
          colors: [[$r('app.color.lb_primary'), 0.0], [$r('app.color.lb_accent'), 1.0]]
        })

        Column({ space: 2 }) {
          Text('逐光')
            .fontSize(FontSize.TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.lb_ink'))
          Text('LightBearing · API 26')
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.lb_muted'))
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: Spacing.S, right: Spacing.S, top: Spacing.XL, bottom: Spacing.XXL })
      .alignItems(VerticalAlign.Center)

      Text('PAGES / 页面')
        .fontSize(NAV_CAPTION_SIZE)
        .fontWeight(FontWeight.Bold)
        .letterSpacing(NAV_CAPTION_SPACING)
        .fontColor($r('app.color.lb_muted'))
        .width('100%')
        .padding({ left: Spacing.M, right: Spacing.M, top: Spacing.M, bottom: Spacing.M })

      ForEach(this.allItems, (item: NavItem) => {
        Row({ space: Spacing.M }) {
          Image(this.currentRoute === item.route ? item.iconInk : item.iconMuted)
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
          Text(item.label)
            .fontSize(FontSize.NAV)
            .fontColor(this.currentRoute === item.route
              ? $r('app.color.lb_ink') : $r('app.color.lb_muted'))
            .layoutWeight(1)
            .maxLines(1)
        }
        .width('100%')
        .height(MIN_TOUCH)
        .padding({ left: Spacing.M, right: Spacing.M })
        .backgroundColor(this.currentRoute === item.route
          ? $r('app.color.lb_nav_active_bg') : Color.Transparent)
        .borderRadius(Radius.BUTTON)
        .borderWidth(1)
        .borderColor(this.currentRoute === item.route
          ? $r('app.color.lb_nav_active_border') : Color.Transparent)
        .onClick(() => {
          this.go(item.route);
        })
        .accessibilityText(item.label)
      }, (item: NavItem) => `rail_${item.route}`)
    }
    .width(212)
    .height('100%')
    .padding({ left: Spacing.M, right: Spacing.M, top: Spacing.S })
    .backgroundColor($r('app.color.lb_panel'))
    .border({ width: { right: 1 }, color: $r('app.color.lb_line') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  onboardingOverlay() {
    Column({ space: Spacing.L }) {
      Stack({ alignContent: Alignment.Center }) {
        Image($r('app.media.ic_sun_bg'))
          .width(40)
          .height(40)
          .objectFit(ImageFit.Contain)
      }
      .width(72)
      .height(72)
      .borderRadius(24)
      .linearGradient({
        angle: 130,
        colors: [[$r('app.color.lb_primary'), 0.0], [$r('app.color.lb_accent'), 1.0]]
      })

      Text('好光线，值得提前抵达')
        .fontSize(FontSize.HERO_H2)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.lb_ink'))
        .textAlign(TextAlign.Center)
      Text('逐光按真实经纬度与时间计算太阳方位、日出日落、黄金与蓝调时刻，帮你提前规划机位。全部数据保存在本机，不联网、不埋点。')
        .fontSize(FontSize.SMALL)
        .fontColor($r('app.color.lb_muted'))
        .lineHeight(22)
        .textAlign(TextAlign.Center)
      Text('第一步：新增一个机位（可手动输入经纬度，或使用当前位置）。')
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_accent'))
        .textAlign(TextAlign.Center)
      Button('开始使用')
        .type(ButtonType.Normal)
        .width('100%')
        .height(MIN_TOUCH)
        .borderRadius(Radius.BUTTON)
        .backgroundColor($r('app.color.lb_primary'))
        .fontColor($r('app.color.lb_on_primary'))
        .fontWeight(FontWeight.Bold)
        .onClick(() => {
          this.finishOnboarding();
        })
      Button('跳过引导')
        .type(ButtonType.Normal)
        .width('100%')
        .height(MIN_TOUCH)
        .borderRadius(Radius.BUTTON)
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.lb_ink'))
        .fontWeight(FontWeight.Bold)
        .borderWidth(1)
        .borderColor($r('app.color.lb_line'))
        .onClick(() => {
          this.finishOnboarding();
        })
    }
    .width('100%')
    .padding(Spacing.XXL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.HERO)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .margin(Spacing.XL)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack() {
      Row() {
        if (this.isTablet) {
          this.rail()
        }
        Column() {
          if (this.bootError.length > 0) {
            Column({ space: Spacing.M }) {
              Text('启动失败')
                .fontSize(FontSize.TITLE)
                .fontColor($r('app.color.lb_ink'))
              Text(this.bootError)
                .fontSize(FontSize.BODY)
                .fontColor($r('app.color.lb_muted'))
              Button('重试')
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .borderRadius(Radius.BUTTON)
                .backgroundColor($r('app.color.lb_primary'))
                .fontColor($r('app.color.lb_on_primary'))
                .fontWeight(FontWeight.Bold)
                .onClick(() => {
                  this.ready = false;
                  this.bootError = '';
                  this.bootstrap();
                })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .padding(Spacing.XXL)
          } else {
            Navigation(this.pathStack) {
              HomePage({
                refreshToken: this.homeToken,
                onNavigate: (route: string) => {
                  this.go(route);
                }
              })
            }
            .navDestination(this.destinationBuilder)
            .hideTitleBar(true)
            .mode(NavigationMode.Stack)
            .layoutWeight(1)
            .width('100%')
            .backgroundColor(Color.Transparent)
          }
          if (!this.isTablet) {
            this.bottomBar()
          }
        }
        .layoutWeight(1)
        .height('100%')
      }
      .width('100%')
      .height('100%')

      if (!this.ready) {
        Column({ space: Spacing.M }) {
          LoadingProgress().width(44).height(44).color($r('app.color.lb_primary'))
          Text('逐光正在准备本地数据…')
            .fontSize(FontSize.BODY)
            .fontColor($r('app.color.lb_muted'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.lb_bg'))
      }

      if (this.showOnboarding) {
        Column() {
          this.onboardingOverlay()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#B3060C14')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.lb_bg'))
    .radialGradient({
      center: ['84%', '0%'],
      radius: 520,
      colors: [[$r('app.color.lb_hero_glow'), 0.0], ['#00000000', 1.0]]
    })
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const width = Number.parseFloat(`${newArea.width}`);
      this.isTablet = width >= 600;
    })
  }
}
