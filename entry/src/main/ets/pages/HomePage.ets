import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH, ThemeColors } from '../common/Theme';
import { Place, ShootPlan, Candidate } from '../model/Models';
import { SolarCalc, SunPosition, SolarEvents, LightPhase, LightWindow } from '../services/SolarCalc';
import { TimeUtil } from '../services/TimeUtil';
import { LocationService, LocationResult } from '../services/LocationService';
import { TopBar, SectionCard, MetricTile, StatusBadge, EmptyState, ErrorCard, NoticeBar,
  PermissionGate, ProjectTile, HeroCard, SkeletonCard, Dialogs } from '../components/Widgets';
import { SunPathChart } from '../components/Charts';

/**
 * S01 今日光线：当前机位 + 今日太阳高度/方位 + 光线时段。
 * 数据全部来自 AppDb/AppState 与实时算法，无演示数组。
 */
@Component
export struct HomePage {
  onNavigate: (route: string) => void = () => {
  };
  /** 父级在回到首页时递增，触发重新读取本地数据 */
  @Prop @Watch('onRefreshToken') refreshToken: number = 0;
  /** 用于强制父级刷新主题色（Canvas 需要具体色值） */
  @State colors: ThemeColors = new ThemeColors();
  @State ready: boolean = false;
  @State errorText: string = '';
  @State showPermissionGate: boolean = false;
  @State locating: boolean = false;
  @State nowUtc: number = 0;
  @State selectedUtc: number = 0;
  @State sliderMinutes: number = 0;
  @State placeName: string = '';
  @State tzId: string = '';
  @State posAz: number = 0;
  @State posAlt: number = 0;
  @State phaseLabel: string = '';
  @State phaseValue: number = 0;
  @State sunriseText: string = '--:--';
  @State sunsetText: string = '--:--';
  @State goldenAmText: string = '--:--';
  @State goldenPmText: string = '--:--';
  @State blueAmText: string = '--:--';
  @State bluePmText: string = '--:--';
  @State civilText: string = '--:--';
  @State polarText: string = '';
  @State dayStartUtc: number = 0;
  @State todayPlans: ShootPlan[] = [];
  @State locationHint: string = '';
  @State hasPlace: boolean = false;
  @State isTablet: boolean = false;

  aboutToAppear(): void {
    this.loadAll();
  }

  onRefreshToken(): void {
    this.loadAll();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async loadAll(): Promise<void> {
    try {
      this.errorText = '';
      const ctx = this.hostContext();
      await AppState.bootstrap(ctx);
      this.colors = ThemeColors.load(ctx);
      this.nowUtc = TimeUtil.now();
      const place = AppState.currentPlace;
      if (place === undefined) {
        this.hasPlace = false;
        this.ready = true;
        this.tzId = AppState.effectiveTzId();
        this.dayStartUtc = TimeUtil.startOfLocalDay(this.tzId, this.nowUtc);
        return;
      }
      this.hasPlace = true;
      this.placeName = place.name;
      this.tzId = place.tzId;
      this.dayStartUtc = TimeUtil.startOfLocalDay(place.tzId, this.nowUtc);
      this.selectedUtc = this.nowUtc;
      const local = TimeUtil.toLocal(place.tzId, this.nowUtc);
      this.sliderMinutes = local.hour * 60 + local.minute;
      this.recompute(place, this.selectedUtc);
      this.loadPlans(place);
      this.ready = true;
    } catch (err) {
      this.errorText = `读取本地数据失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private loadPlans(place: Place): void {
    this.todayPlans = AppState.plansForPlace(place.id);
  }

  private recompute(place: Place, selectedUtc: number): void {
    const th = AppState.thresholds();
    const pos: SunPosition = SolarCalc.position(selectedUtc, place.latWgs84, place.lonWgs84);
    this.posAz = pos.azimuthDeg;
    this.posAlt = pos.altitudeDeg;
    const phase: LightPhase = SolarCalc.phaseOf(pos.altitudeDeg, th);
    this.phaseValue = phase;
    this.phaseLabel = SolarCalc.phaseLabel(phase);

    const ev: SolarEvents = SolarCalc.events(this.dayStartUtc, place.latWgs84, place.lonWgs84);
    this.sunriseText = ev.sunriseUtc < 0 ? '无' : TimeUtil.formatTime(place.tzId, ev.sunriseUtc);
    this.sunsetText = ev.sunsetUtc < 0 ? '无' : TimeUtil.formatTime(place.tzId, ev.sunsetUtc);
    this.civilText = ev.civilDuskUtc < 0 ? '无' : TimeUtil.formatTime(place.tzId, ev.civilDuskUtc);
    if (ev.polarState === 1) {
      this.polarText = '当日极昼：太阳全天位于地平线以上，无常规日出日落。';
    } else if (ev.polarState === 2) {
      this.polarText = '当日极夜：太阳全天位于地平线以下，无常规日出日落。';
    } else {
      this.polarText = '';
    }

    const w: LightWindow = SolarCalc.lightWindows(this.dayStartUtc, place.latWgs84, place.lonWgs84, th);
    this.goldenAmText = w.goldenMorningStartUtc < 0 ? '无'
      : `${TimeUtil.formatTime(place.tzId, w.goldenMorningStartUtc)}-${TimeUtil.formatTime(place.tzId, w.goldenMorningEndUtc)}`;
    this.goldenPmText = w.goldenEveningStartUtc < 0 ? '无'
      : `${TimeUtil.formatTime(place.tzId, w.goldenEveningStartUtc)}-${TimeUtil.formatTime(place.tzId, w.goldenEveningEndUtc)}`;
    this.blueAmText = w.blueMorningStartUtc < 0 ? '无'
      : `${TimeUtil.formatTime(place.tzId, w.blueMorningStartUtc)}-${TimeUtil.formatTime(place.tzId, w.blueMorningEndUtc)}`;
    this.bluePmText = w.blueEveningStartUtc < 0 ? '无'
      : `${TimeUtil.formatTime(place.tzId, w.blueEveningStartUtc)}-${TimeUtil.formatTime(place.tzId, w.blueEveningEndUtc)}`;
  }

  private onSliderChange(minutes: number): void {
    this.sliderMinutes = minutes;
    const place = AppState.currentPlace;
    if (place === undefined) {
      return;
    }
    const local = TimeUtil.toLocal(place.tzId, this.dayStartUtc);
    const hour = Math.floor(minutes / 60);
    const minute = Math.round(minutes % 60);
    this.selectedUtc = TimeUtil.fromLocal(place.tzId, local.year, local.month, local.day, hour, minute);
    this.recompute(place, this.selectedUtc);
  }

  private async useCurrentLocation(): Promise<void> {
    this.locating = true;
    this.locationHint = '';
    try {
      const result: LocationResult = await LocationService.locateOnce(this.hostContext());
      if (result.point === undefined) {
        this.locationHint = result.failure === undefined ? '定位失败' : result.failure.message;
        this.showPermissionGate = result.failure !== undefined && result.failure.code === 1;
        return;
      }
      const tz = this.tzId.length > 0 ? this.tzId : TimeUtil.deviceTimeZoneId();
      const place = AppState.buildPlace(`当前位置 ${result.point.latWgs84.toFixed(3)}, ${result.point.lonWgs84.toFixed(3)}`,
        result.point.latWgs84, result.point.lonWgs84, tz, '定位');
      place.note = `精度约 ${Math.round(result.point.accuracyM)} 米`;
      await AppState.savePlace(place);
      this.showPermissionGate = false;
      await this.loadAll();
      Dialogs.toast(this.getUIContext(), '已保存当前位置为机位');
    } catch (err) {
      this.locationHint = `定位失败：${(err as Error).message}`;
    } finally {
      this.locating = false;
    }
  }

  @Builder
  heroCard() {
    Column({ space: Spacing.M }) {
      Row({ space: Spacing.S }) {
        Text(this.placeName)
          .fontSize(FontSize.BODY_L)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.lb_ink'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        StatusBadge({ label: this.phaseLabel, tone: this.phaseValue === 5 ? 1 : 2 })
      }
      .width('100%')

      Text(`${TimeUtil.formatDate(this.tzId, this.selectedUtc)} ${TimeUtil.weekdayLabel(TimeUtil.weekday(this.tzId, this.selectedUtc))} · ${TimeUtil.formatTime(this.tzId, this.selectedUtc)} · ${TimeUtil.offsetLabel(this.tzId, this.selectedUtc)}`)
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.lb_muted'))

      Row({ space: Spacing.S }) {
        MetricTile({
          valueText: `${this.posAz.toFixed(1)}°`,
          labelText: `太阳方位 · ${SolarCalc.azimuthLabel(this.posAz)}`,
          highlight: true
        })
        MetricTile({
          valueText: `${this.posAlt.toFixed(1)}°`,
          labelText: '太阳高度角'
        })
        MetricTile({
          valueText: SolarCalc.phaseShort(this.phaseValue),
          labelText: '光线阶段',
          highlight: this.phaseValue === 5
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(Spacing.XL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  timeSection() {
    Column({ space: Spacing.S }) {
      SunPathChart({
        lat: AppState.currentPlace === undefined ? 0 : AppState.currentPlace.latWgs84,
        lon: AppState.currentPlace === undefined ? 0 : AppState.currentPlace.lonWgs84,
        tzId: this.tzId,
        dayStartUtc: this.dayStartUtc,
        selectedUtc: this.selectedUtc,
        goldenUpper: AppState.settings.goldenUpper,
        goldenLower: AppState.settings.goldenLower,
        blueLower: AppState.settings.blueLower,
        chartHeight: 200
      })
      Slider({
        value: this.sliderMinutes,
        min: 0,
        max: 1439,
        step: 1,
        style: SliderStyle.OutSet
      })
        .selectedColor($r('app.color.lb_primary'))
        .trackColor($r('app.color.lb_panel2'))
        .blockColor($r('app.color.lb_primary'))
        .width('100%')
        .onChange((value: number, mode: SliderChangeMode) => {
          this.onSliderChange(Math.round(value));
        })
        .accessibilityText('拖动选择今日时刻')
      Text('拖动调整时刻，曲线为按当前机位坐标实时计算的全天太阳高度角。')
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.lb_muted'))
    }
    .width('100%')
    .padding(Spacing.XL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  eventsSection() {
    Column({ space: Spacing.S }) {
      Text('今日光线时刻')
        .fontSize(FontSize.BODY_L)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.lb_ink'))
      this.eventRow('日出', this.sunriseText)
      this.eventRow('日落', this.sunsetText)
      this.eventRow('黄金时刻（晨）', this.goldenAmText)
      this.eventRow('黄金时刻（夕）', this.goldenPmText)
      this.eventRow('蓝调时刻（晨）', this.blueAmText)
      this.eventRow('蓝调时刻（夕）', this.bluePmText)
      this.eventRow('民用曙光结束', this.civilText)
      if (this.polarText.length > 0) {
        NoticeBar({ text: this.polarText })
      }
      NoticeBar({
        text: '算法：NOAA/Meeus 低精度级数；日出日落按上边缘 + 标准折射，几何高度 -0.833°。未含海拔对地平线的俯角修正。'
      })
    }
    .width('100%')
    .padding(Spacing.XL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  eventRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_muted'))
        .layoutWeight(1)
      Text(value)
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_ink'))
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .constraintSize({ minHeight: 28 })
  }

  @Builder
  planSection() {
    Column({ space: Spacing.S }) {
      Row() {
        Text('本机位计划')
          .fontSize(FontSize.BODY_L)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.lb_ink'))
          .layoutWeight(1)
        Text(`${this.todayPlans.length} 条`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
      }
      .width('100%')

      if (this.todayPlans.length === 0) {
        Text('还没有拍摄计划。可在「拍摄计划」中保存目标机位与候选窗口。')
          .fontSize(FontSize.BODY)
          .fontColor($r('app.color.lb_muted'))
      } else {
        ForEach(this.todayPlans.slice(0, 3), (plan: ShootPlan) => {
          ProjectTile({
            primary: plan.placeName.length > 0 ? plan.placeName : '未命名计划',
            secondary: `${TimeUtil.formatDate(plan.tzId, plan.selectedUtc)} ${TimeUtil.formatTime(plan.tzId, plan.selectedUtc)} · 目标 ${plan.targetAzimuth.toFixed(0)}°`,
            meta: plan.note,
            statusText: plan.status === 0 ? '草稿' : (plan.status === 1 ? '已确认' : '已完成'),
            statusTone: plan.status === 1 ? 1 : 3,
            iconSrc: $r('app.media.ic_calendar_primary'),
            onTap: () => {
              this.onNavigate('planner');
            }
          })
        }, (plan: ShootPlan) => plan.id)
      }
    }
    .width('100%')
    .padding(Spacing.XL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  emptyBlock() {
    Column({ space: Spacing.M }) {
      EmptyState({
        title: '先确定一个机位',
        description: '逐光只在本地计算。你可以使用当前的定位建立机位，或手动输入经纬度。没有定位与网络时全部功能依然可用。',
        actionLabel: '手动输入经纬度',
        onAction: () => {
          this.onNavigate('locations');
        }
      })
      if (this.locationHint.length > 0) {
        NoticeBar({ text: this.locationHint })
      }
      if (this.showPermissionGate) {
        PermissionGate({
          title: '定位权限被拒绝',
          reason: '「使用当前位置」需要前台一次定位权限。拒绝后仍可用手动坐标完成全部计算。',
          grantLabel: '重新授权',
          fallbackLabel: '手动输入',
          onGrant: () => {
            this.useCurrentLocation();
          },
          onFallback: () => {
            this.onNavigate('locations');
          }
        })
      } else {
        Button(this.locating ? '正在定位…' : '使用当前位置')
          .type(ButtonType.Normal)
          .width('100%')
          .height(MIN_TOUCH)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_primary'))
          .fontColor($r('app.color.lb_bg'))
          .enabled(!this.locating)
          .onClick(() => {
            this.useCurrentLocation();
          })
      }
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({
          title: '今日光线',
          subtitle: '当前位置或手动地点的今日时段与太阳高度/方位',
          chipText: '本地计算'
        })

        HeroCard({
          heroTitle: '好光线，值得提前抵达',
          heroBody: '逐光按真实经纬度与时间计算太阳方位、日出日落与黄金/蓝调时刻，帮你提前定好机位和时刻。全部计算在本机完成，不联网、不埋点。',
          primaryLabel: '反向查找好光线',
          ghostLabel: '查看完整日轨',
          onPrimary: () => {
            this.onNavigate('reverse');
          },
          onGhost: () => {
            this.onNavigate('sunpath');
          }
        })

        if (this.errorText.length > 0) {
          ErrorCard({
            message: this.errorText,
            onRetry: () => {
              this.loadAll();
            },
            onBack: () => {
              this.onNavigate('settings');
            }
          })
        } else if (!this.ready) {
          Column({ space: Spacing.M }) {
            SkeletonCard()
            SkeletonCard()
          }
          .width('100%')
        } else if (!this.hasPlace) {
          this.emptyBlock()
        } else {
          this.heroCard()
          if (this.isTablet) {
            // 平板：图表与光线时刻双栏并排（任务书 §0「平板图表双栏」）
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              Column() {
                this.timeSection()
              }
              .width('49%')

              Column() {
                this.eventsSection()
              }
              .width('49%')
            }
            .width('100%')
          } else {
            this.timeSection()
            this.eventsSection()
          }
          this.planSection()
        }
      }
      .width('100%')
      .padding({ bottom: Spacing.XXXL, left: this.isTablet ? 0 : Spacing.S, right: this.isTablet ? 0 : Spacing.S })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const width = Number.parseFloat(`${newArea.width}`);
      this.isTablet = width >= 600;
    })
  }
}
