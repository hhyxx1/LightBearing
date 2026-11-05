import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH, ThemeColors } from '../common/Theme';
import { Place, ShootPlan, Candidate } from '../model/Models';
import { SolarCalc, SunPosition, SolarEvents, LightPhase, LightWindow, EventState, WindowState } from '../services/SolarCalc';
import { TimeUtil } from '../services/TimeUtil';
import { Timeline, TimelineModel } from '../services/Timeline';
import { SliderMapping, SliderValue, EventText } from '../services/TimeSelection';
import { LocationService, LocationResult } from '../services/LocationService';
import { TopBar, SectionCard, MetricTile, StatusBadge, EmptyState, ErrorCard, NoticeBar,
  PermissionGate, ProjectTile, HeroCard, SkeletonCard, Dialogs } from '../components/Widgets';
import { SunPathChart } from '../components/Charts';
import { ObservationPanel } from '../components/ObservationPanel';
import { ObservationBands } from '../services/ObservationBands';

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
  /** >=1200vp：三区工作台 */
  @State isWide: boolean = false;
  /** 真实时段区间（UTC 对），由 SolarCalc.lightWindows 计算 */
  @State goldenPairs: number[] = [];
  @State bluePairs: number[] = [];
  /** 外壳发布的内容宽度（扣除导航栏），用于统一断点 */
  @StorageProp('lbContentWidth') contentWidth: number = 0;
  @StorageProp('lbThemeStamp') themeStamp: number = 0;
  @State showPermissionGate: boolean = false;
  @State locating: boolean = false;
  @State nowUtc: number = 0;
  @State selectedUtc: number = 0;
  @State sliderProgress: number = 500;
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
  @State dayEndUtc: number = 0;
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

  /** 用真实本地日边界（夏令时切换日可能是 23/25 小时）；不可用时置 0，界面按「无」处理 */
  private applyDayBounds(tzId: string, utcMs: number): void {
    const local = TimeUtil.toLocal(tzId, utcMs);
    if (!local.valid) {
      this.dayStartUtc = 0;
      this.dayEndUtc = 0;
      return;
    }
    const bounds = TimeUtil.localDayBounds(tzId, local.year, local.month, local.day);
    this.dayStartUtc = bounds.valid ? bounds.startUtc : 0;
    this.dayEndUtc = bounds.valid ? bounds.endUtc : 0;
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
        this.applyDayBounds(this.tzId, this.nowUtc);
        return;
      }
      this.hasPlace = true;
      this.placeName = place.name;
      this.tzId = place.tzId;
      this.applyDayBounds(place.tzId, this.nowUtc);
      this.selectedUtc = this.nowUtc;
      const local = TimeUtil.toLocal(place.tzId, this.nowUtc);
      const initModel: TimelineModel = Timeline.fromBounds(this.dayStartUtc, this.dayEndUtc);
      const initSlider: SliderValue = SliderMapping.toSlider(initModel, this.selectedUtc);
      this.sliderProgress = initSlider.valid ? initSlider.value : 500;
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
    // 时区数据异常时 selectedUtc 可能是 NaN：不允许把 NaN 传进 position()
    if (!Number.isFinite(selectedUtc)) {
      this.posAz = 0;
      this.posAlt = 0;
      this.phaseLabel = '时间不可用';
      this.sunriseText = '无';
      this.sunsetText = '无';
      this.civilText = '无';
      this.polarText = '机位时区或日期数据不可用，无法计算太阳位置。';
      this.goldenAmText = '无';
      this.goldenPmText = '无';
      this.blueAmText = '无';
      this.bluePmText = '无';
      return;
    }
    const pos: SunPosition = SolarCalc.position(selectedUtc, place.latWgs84, place.lonWgs84);
    this.posAz = pos.azimuthDeg;
    this.posAlt = pos.altitudeDeg;
    const phase: LightPhase = SolarCalc.phaseOf(pos.altitudeDeg, th);
    this.phaseValue = phase;
    this.phaseLabel = SolarCalc.phaseLabel(phase);

    const ev: SolarEvents = SolarCalc.events(this.dayStartUtc, place.latWgs84, place.lonWgs84, this.dayEndUtc);
    this.sunriseText = EventText.describe(ev.sunriseState, TimeUtil.formatTime(place.tzId, ev.sunriseUtc));
    this.sunsetText = EventText.describe(ev.sunsetState, TimeUtil.formatTime(place.tzId, ev.sunsetUtc));
    this.civilText = EventText.describe(ev.civilDuskState, TimeUtil.formatTime(place.tzId, ev.civilDuskUtc));
    if (!ev.dayValid) {
      this.polarText = '本地日边界不可用，无法判定当日太阳事件。';
    } else if (ev.polarState === 1) {
      this.polarText = '当日极昼：太阳全天位于地平线以上，无常规日出日落。';
    } else if (ev.polarState === 2) {
      this.polarText = '当日极夜：太阳全天位于地平线以下，无常规日出日落。';
    } else {
      this.polarText = '';
    }

    const w: LightWindow = SolarCalc.lightWindows(this.dayStartUtc, place.latWgs84, place.lonWgs84, th,
      this.dayEndUtc);
    this.goldenPairs = ObservationBands.clippedPairs(ObservationBands.goldenPairs(w),
      this.dayStartUtc, this.dayEndUtc);
    this.bluePairs = ObservationBands.clippedPairs(ObservationBands.bluePairs(w),
      this.dayStartUtc, this.dayEndUtc);
    this.goldenAmText = w.goldenMorningState === WindowState.AVAILABLE
      ? `${TimeUtil.formatTime(place.tzId, w.goldenMorningStartUtc)}-${TimeUtil.formatTime(place.tzId, w.goldenMorningEndUtc)}`
      : '无';
    this.goldenPmText = w.goldenEveningState === WindowState.AVAILABLE
      ? `${TimeUtil.formatTime(place.tzId, w.goldenEveningStartUtc)}-${TimeUtil.formatTime(place.tzId, w.goldenEveningEndUtc)}`
      : '无';
    this.blueAmText = w.blueMorningState === WindowState.AVAILABLE
      ? `${TimeUtil.formatTime(place.tzId, w.blueMorningStartUtc)}-${TimeUtil.formatTime(place.tzId, w.blueMorningEndUtc)}`
      : '无';
    this.bluePmText = w.blueEveningState === WindowState.AVAILABLE
      ? `${TimeUtil.formatTime(place.tzId, w.blueEveningStartUtc)}-${TimeUtil.formatTime(place.tzId, w.blueEveningEndUtc)}`
      : '无';
  }

  private onSliderChange(progress: number): void {
    this.sliderProgress = progress;
    const place = AppState.currentPlace;
    if (place === undefined) {
      return;
    }
    // Slider 是真实 UTC 时间轴上的位置：DST 缺口不会被选中，重复小时各有独立位置
    const model: TimelineModel = Timeline.fromBounds(this.dayStartUtc, this.dayEndUtc);
    const point = SliderMapping.toUtc(model, progress);
    if (!point.valid) {
      return;
    }
    this.selectedUtc = point.utcMs;
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
        dayEndUtc: this.dayEndUtc,
        selectedUtc: this.selectedUtc,
        goldenUpper: AppState.settings.goldenUpper,
        goldenLower: AppState.settings.goldenLower,
        blueLower: AppState.settings.blueLower,
        chartHeight: 200
      })
      Slider({
        value: this.sliderProgress,
        min: 0,
        max: 1000,
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
        .accessibilityText('拖动选择今日时刻（按真实本地日时间轴，夏令时缺口会自动跳过）')
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


  /** 顶部：页面标题 + 本地计算标识（替代大欢迎语） */
  @Builder
  slimHeader() {
    Row({ space: Spacing.S }) {
      Column({ space: Spacing.XS }) {
        Text('今日光线')
          .fontSize(FontSize.H1)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.lb_ink'))
        Text('太阳方位、轨迹与可拍时段')
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('本地计算')
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.lb_primary'))
        .padding({ left: Spacing.M, right: Spacing.M, top: Spacing.S, bottom: Spacing.S })
        .borderRadius(Radius.CHIP)
        .borderWidth(1)
        .borderColor($r('app.color.lb_primary'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 机位条：机位名 + 当地日期/UTC 偏移 + 阶段 */
  @Builder
  stationHeader() {
    Row({ space: Spacing.S }) {
      Column({ space: Spacing.XS }) {
        Text(this.placeName.length > 0 ? this.placeName : '未选择机位')
          .fontSize(FontSize.HERO_H2)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.lb_ink'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${TimeUtil.formatDate(this.tzId, this.selectedUtc)} ${TimeUtil.weekdayLabel(TimeUtil.weekday(this.tzId, this.selectedUtc))} · ${TimeUtil.offsetLabel(this.tzId, this.selectedUtc)}`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      StatusBadge({ label: this.phaseLabel, tone: this.phaseValue === 5 ? 1 : 2 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 当前光线仪表盘：方位/高度为主数字 */
  @Builder
  instrumentPanel() {
    Column({ space: Spacing.M }) {
      Row() {
        Text('当前光线')
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
          .layoutWeight(1)
        Text(`${TimeUtil.formatTime(this.tzId, this.selectedUtc)} · ${TimeUtil.offsetLabel(this.tzId, this.selectedUtc)}`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
      }
      .width('100%')

      Row({ space: Spacing.M }) {
        Column({ space: Spacing.XS }) {
          Text(`${this.posAz.toFixed(1)}°`)
            .fontSize(FontSize.DISPLAY)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.lb_primary'))
          Text(`方位 · ${SolarCalc.azimuthLabel(this.posAz)}`)
            .fontSize(FontSize.SMALL)
            .fontColor($r('app.color.lb_muted'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: Spacing.XS }) {
          Text(`${this.posAlt.toFixed(1)}°`)
            .fontSize(FontSize.DISPLAY)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.lb_accent'))
          Text('太阳高度角')
            .fontSize(FontSize.SMALL)
            .fontColor($r('app.color.lb_muted'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: Spacing.XS }) {
          Text(SolarCalc.phaseShort(this.phaseValue))
            .fontSize(FontSize.TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.lb_ink'))
          Text('光线阶段')
            .fontSize(FontSize.SMALL)
            .fontColor($r('app.color.lb_muted'))
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding(Spacing.XL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(HorizontalAlign.Start)
  }

  /** 关键时段 2x2 仪表格 */
  @Builder
  eventsGrid() {
    Column({ space: Spacing.S }) {
      Text('今日关键时段')
        .fontSize(FontSize.BODY_L)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.lb_ink'))
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        this.eventTile('日出', this.sunriseText)
        this.eventTile('日落', this.sunsetText)
        this.eventTile('黄金（晨）', this.goldenAmText)
        this.eventTile('黄金（夕）', this.goldenPmText)
      }
      .width('100%')
      if (this.polarText.length > 0) {
        NoticeBar({ text: this.polarText })
      }
      Text('算法：NOAA/Meeus 低精度级数；日出日落按上边缘 + 标准折射（几何高度 -0.833°）。')
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
  eventTile(label: string, value: string) {
    Column({ space: Spacing.XS }) {
      Text(value)
        .fontSize(FontSize.TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.lb_ink'))
      Text(label)
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.lb_muted'))
    }
    .width('49%')
    .padding(Spacing.M)
    .margin({ bottom: Spacing.S })
    .backgroundColor($r('app.color.lb_panel2'))
    .borderRadius(Radius.STAT)
    .alignItems(HorizontalAlign.Start)
  }

  /** 主要操作：反向寻光 / 机位库 */
  @Builder
  quickActions() {
    Row({ space: Spacing.S }) {
      Button('反向寻光')
        .type(ButtonType.Normal)
        .height(MIN_TOUCH)
        .layoutWeight(1)
        .borderRadius(Radius.BUTTON)
        .backgroundColor($r('app.color.lb_primary'))
        .fontColor($r('app.color.lb_on_primary'))
        .fontSize(FontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .onClick(() => {
          this.onNavigate('reverse');
        })
      Button('机位库')
        .type(ButtonType.Normal)
        .height(MIN_TOUCH)
        .layoutWeight(1)
        .borderRadius(Radius.BUTTON)
        .backgroundColor($r('app.color.lb_panel2'))
        .fontColor($r('app.color.lb_ink'))
        .fontSize(FontSize.BODY)
        .onClick(() => {
          this.onNavigate('locations');
        })
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: Spacing.S }) {
        this.slimHeader()
        this.stationHeader()

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
        } else if (this.isWide) {
          Row({ space: Spacing.M }) {
            Column({ space: Spacing.M }) {
          ObservationPanel({
            placeName: this.placeName,
            tzId: this.tzId,
            lat: AppState.currentPlace === undefined ? 0 : AppState.currentPlace.latWgs84,
            lon: AppState.currentPlace === undefined ? 0 : AppState.currentPlace.lonWgs84,
            dayStartUtc: this.dayStartUtc,
            dayEndUtc: this.dayEndUtc,
            selectedUtc: this.selectedUtc,
            sliderProgress: this.sliderProgress,
            posAz: this.posAz,
            posAlt: this.posAlt,
            phaseLabel: this.phaseLabel,
            phaseShort: SolarCalc.phaseShort(this.phaseValue),
            selectedTimeText: TimeUtil.formatTime(this.tzId, this.selectedUtc),
            offsetText: TimeUtil.offsetLabel(this.tzId, this.selectedUtc),
            sunriseText: this.sunriseText,
            sunsetText: this.sunsetText,
            goldenPairs: this.goldenPairs,
            bluePairs: this.bluePairs,
            goldenUpper: AppState.settings.goldenUpper,
            goldenLower: AppState.settings.goldenLower,
            blueLower: AppState.settings.blueLower,
            polarText: this.polarText,
            chartHeight: this.isWide ? 260 : 200,
            themeStamp: this.themeStamp,
            onSlide: (progress: number) => {
              this.onSliderChange(progress);
            }
          })
              this.eventsGrid()
            }
            .layoutWeight(1)

            Column({ space: Spacing.M }) {
              this.planSection()
              this.quickActions()
            }
            .width(320)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else if (this.isTablet) {
          Row({ space: Spacing.M }) {
            Column({ space: Spacing.M }) {
          ObservationPanel({
            placeName: this.placeName,
            tzId: this.tzId,
            lat: AppState.currentPlace === undefined ? 0 : AppState.currentPlace.latWgs84,
            lon: AppState.currentPlace === undefined ? 0 : AppState.currentPlace.lonWgs84,
            dayStartUtc: this.dayStartUtc,
            dayEndUtc: this.dayEndUtc,
            selectedUtc: this.selectedUtc,
            sliderProgress: this.sliderProgress,
            posAz: this.posAz,
            posAlt: this.posAlt,
            phaseLabel: this.phaseLabel,
            phaseShort: SolarCalc.phaseShort(this.phaseValue),
            selectedTimeText: TimeUtil.formatTime(this.tzId, this.selectedUtc),
            offsetText: TimeUtil.offsetLabel(this.tzId, this.selectedUtc),
            sunriseText: this.sunriseText,
            sunsetText: this.sunsetText,
            goldenPairs: this.goldenPairs,
            bluePairs: this.bluePairs,
            goldenUpper: AppState.settings.goldenUpper,
            goldenLower: AppState.settings.goldenLower,
            blueLower: AppState.settings.blueLower,
            polarText: this.polarText,
            chartHeight: this.isWide ? 260 : 200,
            themeStamp: this.themeStamp,
            onSlide: (progress: number) => {
              this.onSliderChange(progress);
            }
          })
            }
            .layoutWeight(1)

            Column({ space: Spacing.M }) {
              this.eventsGrid()
              this.planSection()
            }
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else {
          ObservationPanel({
            placeName: this.placeName,
            tzId: this.tzId,
            lat: AppState.currentPlace === undefined ? 0 : AppState.currentPlace.latWgs84,
            lon: AppState.currentPlace === undefined ? 0 : AppState.currentPlace.lonWgs84,
            dayStartUtc: this.dayStartUtc,
            dayEndUtc: this.dayEndUtc,
            selectedUtc: this.selectedUtc,
            sliderProgress: this.sliderProgress,
            posAz: this.posAz,
            posAlt: this.posAlt,
            phaseLabel: this.phaseLabel,
            phaseShort: SolarCalc.phaseShort(this.phaseValue),
            selectedTimeText: TimeUtil.formatTime(this.tzId, this.selectedUtc),
            offsetText: TimeUtil.offsetLabel(this.tzId, this.selectedUtc),
            sunriseText: this.sunriseText,
            sunsetText: this.sunsetText,
            goldenPairs: this.goldenPairs,
            bluePairs: this.bluePairs,
            goldenUpper: AppState.settings.goldenUpper,
            goldenLower: AppState.settings.goldenLower,
            blueLower: AppState.settings.blueLower,
            polarText: this.polarText,
            chartHeight: this.isWide ? 260 : 200,
            themeStamp: this.themeStamp,
            onSlide: (progress: number) => {
              this.onSliderChange(progress);
            }
          })
          this.eventsGrid()
          this.planSection()
          this.quickActions()
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
      // 优先使用外壳发布的内容宽度（已扣除 212vp 导航栏），避免两套断点互相冲突
      const effective = this.contentWidth > 0 ? this.contentWidth : width;
      this.isTablet = effective >= 600;
      this.isWide = effective >= 1200;
    })
  }
}
