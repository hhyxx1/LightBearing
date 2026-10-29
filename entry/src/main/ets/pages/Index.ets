import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH, Theme } from '../common/Theme';
import { AppDb } from '../repository/AppDb';
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

/** 一级导航项 */
class NavItem {
  route: string = '';
  label: string = '';
  glyph: string = '';

  static of(route: string, label: string, glyph: string): NavItem {
    const n = new NavItem();
    n.route = route;
    n.label = label;
    n.glyph = glyph;
    return n;
  }
}

/**
 * 应用外壳：Navigation + NavDestination。
 *
 * - 手机：底部 4 个一级入口（今日/轨迹/计划/设置）+「更多」二级路由；
 * - 平板：左侧固定导航栏，全部 10 个路由直接可达；
 * - 全部页面共享同一个 NavPathStack，返回行为一致。
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
    NavItem.of('home', '今日', '☀'),
    NavItem.of('sunpath', '轨迹', '◠'),
    NavItem.of('planner', '计划', '▣'),
    NavItem.of('settings', '设置', '⚙')
  ];

  private allItems: NavItem[] = [
    NavItem.of('home', '今日光线', '☀'),
    NavItem.of('sunpath', '太阳轨迹', '◠'),
    NavItem.of('reverse', '反向寻光', '⇄'),
    NavItem.of('locations', '机位库', '⌖'),
    NavItem.of('compass', '现场罗盘', '✦'),
    NavItem.of('map', '地图方位', '◈'),
    NavItem.of('planner', '拍摄计划', '▣'),
    NavItem.of('calendar', '日历', '▦'),
    NavItem.of('compare', '时间比较', '≈'),
    NavItem.of('settings', '设置', '⚙')
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
      await AppDb.saveSettings(AppState.settings);
    } catch (err) {
      // 引导状态写入失败不阻塞使用
    }
  }

  /** 一级/任意路由跳转：home 回到 Navigation 内容区，其余入栈 */
  private go(route: string): void {
    if (route === 'home') {
      this.pathStack.clear();
      this.currentRoute = 'home';
      this.homeToken = this.homeToken + 1;
      return;
    }
    if (this.currentRoute === route && this.pathStack.size() > 0) {
      return;
    }
    this.pathStack.clear();
    this.pathStack.pushPathByName(route, '');
    this.currentRoute = route;
  }

  private back(): void {
    if (this.pathStack.size() > 0) {
      this.pathStack.pop();
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
  }

  @Builder
  morePage() {
    Scroll() {
      Column({ space: Spacing.M }) {
        Text('更多工具')
          .fontSize(FontSize.H1)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.lb_ink'))
          .width('100%')
        Text('逐光的全部页面都可以从这里直达。')
          .fontSize(FontSize.BODY)
          .fontColor($r('app.color.lb_muted'))
          .width('100%')
        Grid() {
          ForEach(this.allItems, (item: NavItem) => {
            GridItem() {
              Column({ space: Spacing.S }) {
                Text(item.glyph)
                  .fontSize(22)
                  .fontColor($r('app.color.lb_primary'))
                Text(item.label)
                  .fontSize(FontSize.BODY)
                  .fontColor($r('app.color.lb_ink'))
              }
              .width('100%')
              .height(96)
              .justifyContent(FlexAlign.Center)
              .backgroundColor($r('app.color.lb_panel'))
              .borderRadius(Radius.CARD)
              .onClick(() => {
                this.go(item.route);
              })
            }
          }, (item: NavItem) => item.route)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .width('100%')
        .height(360)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .padding(Spacing.L)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  bottomBar() {
    Row() {
      ForEach(this.primaryItems, (item: NavItem) => {
        Column({ space: 2 }) {
          Text(item.glyph)
            .fontSize(18)
            .fontColor(this.currentRoute === item.route ? $r('app.color.lb_primary') : $r('app.color.lb_muted'))
          Text(item.label)
            .fontSize(FontSize.CAPTION)
            .fontColor(this.currentRoute === item.route ? $r('app.color.lb_primary') : $r('app.color.lb_muted'))
        }
        .layoutWeight(1)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.go(item.route);
        })
        .accessibilityText(item.label)
      }, (item: NavItem) => item.route)
      Column({ space: 2 }) {
        Text('⋯')
          .fontSize(18)
          .fontColor($r('app.color.lb_muted'))
        Text('更多')
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
      }
      .layoutWeight(1)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.go('more');
      })
      .accessibilityText('更多工具')
    }
    .width('100%')
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius({ topLeft: Radius.CARD, topRight: Radius.CARD })
  }

  @Builder
  rail() {
    Column({ space: Spacing.XS }) {
      Text('逐光')
        .fontSize(FontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.lb_primary'))
        .width('100%')
        .padding({ left: Spacing.S, top: Spacing.L, bottom: Spacing.M })
      ForEach(this.allItems, (item: NavItem) => {
        Row({ space: Spacing.S }) {
          Text(item.glyph)
            .fontSize(16)
            .fontColor(this.currentRoute === item.route ? $r('app.color.lb_primary') : $r('app.color.lb_muted'))
            .width(22)
          Text(item.label)
            .fontSize(FontSize.BODY)
            .fontColor(this.currentRoute === item.route ? $r('app.color.lb_ink') : $r('app.color.lb_muted'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(MIN_TOUCH)
        .padding({ left: Spacing.M, right: Spacing.M })
        .backgroundColor(this.currentRoute === item.route ? $r('app.color.lb_panel2') : Color.Transparent)
        .borderRadius(Radius.BUTTON)
        .onClick(() => {
          this.go(item.route);
        })
        .accessibilityText(item.label)
      }, (item: NavItem) => item.route)
    }
    .width(184)
    .height('100%')
    .padding({ left: Spacing.S, right: Spacing.S, top: Spacing.M })
    .backgroundColor($r('app.color.lb_panel'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  onboardingOverlay() {
    Column({ space: Spacing.M }) {
      Text('☀')
        .fontSize(52)
        .fontColor($r('app.color.lb_primary'))
      Text('好光线，值得提前抵达')
        .fontSize(FontSize.H1)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.lb_ink'))
        .textAlign(TextAlign.Center)
      Text('逐光按真实经纬度与时间计算太阳方位、日出日落、黄金与蓝调时刻，帮你提前规划机位。全部数据保存在本机，不联网、不埋点。')
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_muted'))
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
        .fontColor($r('app.color.lb_bg'))
        .onClick(() => {
          this.finishOnboarding();
        })
      Button('跳过引导')
        .type(ButtonType.Normal)
        .width('100%')
        .height(MIN_TOUCH)
        .borderRadius(Radius.BUTTON)
        .backgroundColor($r('app.color.lb_panel2'))
        .fontColor($r('app.color.lb_ink'))
        .onClick(() => {
          this.finishOnboarding();
        })
    }
    .width('100%')
    .padding(Spacing.XXL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
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
                .fontColor($r('app.color.lb_bg'))
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
            .backgroundColor($r('app.color.lb_bg'))
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
        .backgroundColor('#CC000000')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.lb_bg'))
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const width = Number.parseFloat(`${newArea.width}`);
      this.isTablet = width >= 600;
    })
  }
}
