import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH } from '../common/Theme';
import { Place, ShootPlan, Candidate, SearchGoal, IdGen } from '../model/Models';
import { SolarCalc } from '../services/SolarCalc';
import { ReverseSearch } from '../services/ReverseSearch';
import { TimeUtil } from '../services/TimeUtil';
import { AppDb } from '../repository/AppDb';
import { TopBar, EmptyState, ErrorCard, NoticeBar, NumberField, StatusBadge, SkeletonCard, Dialogs } from '../components/Widgets';

/**
 * S03 反向寻光：给定方位/高度容差与日期范围，批量搜索满足条件的时刻。
 * 所有候选均由 SolarCalc 现场算出，误差可复算。
 */
@Component
export struct ReversePage {
  onNavigate: (route: string) => void = () => {
  };
  onBack: () => void = () => {
  };
  @State ready: boolean = false;
  @State errorText: string = '';
  @State hasPlace: boolean = false;
  @State placeName: string = '';
  @State tzId: string = '';
  @State azInput: string = '250';
  @State altInput: string = '10';
  @State azTolInput: string = '3';
  @State altTolInput: string = '3';
  @State daysInput: string = '14';
  @State daylightOnly: boolean = false;
  @State searching: boolean = false;
  @State candidates: Candidate[] = [];
  @State searched: boolean = false;
  @State summary: string = '';
  @State lastMs: number = 0;

  aboutToAppear(): void {
    this.initPage();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async initPage(): Promise<void> {
    try {
      await AppState.bootstrap(this.hostContext());
      const place = AppState.currentPlace;
      if (place === undefined) {
        this.hasPlace = false;
        this.ready = true;
        return;
      }
      this.hasPlace = true;
      this.placeName = place.name;
      this.tzId = place.tzId;
      this.ready = true;
    } catch (err) {
      this.errorText = `读取机位失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private parse(value: string, fallback: number): number {
    const v = Number.parseFloat(value);
    return Number.isNaN(v) ? fallback : v;
  }

  private async runSearch(): Promise<void> {
    const place = AppState.currentPlace;
    if (place === undefined) {
      return;
    }
    this.searching = true;
    this.candidates = [];
    this.summary = '';
    try {
      const goal = new SearchGoal();
      goal.placeId = place.id;
      goal.latWgs84 = place.latWgs84;
      goal.lonWgs84 = place.lonWgs84;
      goal.tzId = place.tzId;
      goal.azimuthTarget = SolarCalc.norm360(this.parse(this.azInput, 180));
      goal.altitudeTarget = this.parse(this.altInput, 10);
      goal.azTolerance = Math.max(0.1, this.parse(this.azTolInput, 3));
      goal.altTolerance = Math.max(0.1, this.parse(this.altTolInput, 3));
      const days = Math.max(1, Math.min(365, Math.round(this.parse(this.daysInput, 14))));
      goal.rangeDays = days;
      goal.daylightOnly = this.daylightOnly;
      goal.maxResults = 30;

      const dayStarts: number[] = [];
      let cursor = TimeUtil.startOfLocalDay(place.tzId, TimeUtil.now());
      for (let i = 0; i < days; i++) {
        dayStarts.push(cursor);
        cursor = TimeUtil.addLocalDays(place.tzId, cursor, 1);
      }

      const t0 = new Date().getTime();
      const found = ReverseSearch.search(goal, AppState.thresholds(), dayStarts);
      this.lastMs = new Date().getTime() - t0;
      this.candidates = found;
      this.searched = true;
      this.summary = `在 ${days} 天内按 5 分钟粗扫并逐级细化，命中 ${found.length} 个时间窗口（用时 ${this.lastMs} ms）。`;
      await AppDb.addHistory('reverse',
        `反向寻光 ${place.name} 目标 ${goal.azimuthTarget.toFixed(0)}°/${goal.altitudeTarget.toFixed(0)}° 命中 ${found.length}`,
        `${days}天`);
    } catch (err) {
      this.errorText = `搜索失败：${(err as Error).message}`;
    } finally {
      this.searching = false;
    }
  }

  private async addToPlan(candidate: Candidate): Promise<void> {
    const place = AppState.currentPlace;
    if (place === undefined) {
      return;
    }
    try {
      const plan = new ShootPlan();
      plan.id = IdGen.next('r');
      plan.placeId = place.id;
      plan.placeName = place.name;
      plan.latWgs84 = place.latWgs84;
      plan.lonWgs84 = place.lonWgs84;
      plan.tzId = place.tzId;
      plan.selectedUtc = candidate.utcMs;
      plan.targetAzimuth = candidate.azimuth;
      plan.targetAltitude = candidate.altitude;
      plan.azTolerance = this.parse(this.azTolInput, 3);
      plan.altTolerance = this.parse(this.altTolInput, 3);
      plan.note = `反向寻光命中 · 误差 ${candidate.azError.toFixed(2)}° / ${candidate.altError.toFixed(2)}°`;
      plan.checklist = '[]';
      await AppDb.savePlan(plan, `反向寻光加入计划 · ${place.name}`);
      await AppState.reloadData();
      Dialogs.toast(this.getUIContext(), '已加入拍摄计划');
    } catch (err) {
      Dialogs.toast(this.getUIContext(), `保存失败：${(err as Error).message}`);
    }
  }

  build() {
    Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({ title: '反向寻光', subtitle: '指定方位与高度，找出可达的时间窗口' })

        if (this.errorText.length > 0) {
          ErrorCard({
            message: this.errorText,
            onRetry: () => {
              this.errorText = '';
              this.initPage();
            },
            onBack: () => {
              this.onBack();
            }
          })
        } else if (!this.ready) {
          Column({ space: Spacing.M }) {
            SkeletonCard()
            SkeletonCard()
          }
          .width('100%')
        } else if (!this.hasPlace) {
          EmptyState({
            title: '还没有机位',
            description: '反向寻光需要机位坐标。请先新增机位或使用当前位置。',
            actionLabel: '去机位库',
            onAction: () => {
              this.onNavigate('locations');
            }
          })
        } else {
          Column({ space: Spacing.M }) {
            Text(this.placeName).fontSize(FontSize.BODY).fontColor($r('app.color.lb_muted'))
            NumberField({
              label: '目标方位角', unit: '°', valueText: this.azInput, placeholder: '0-360',
              onChangeText: (text: string) => {
                this.azInput = text;
              }
            })
            NumberField({
              label: '目标高度角', unit: '°', valueText: this.altInput, placeholder: '-90-90',
              onChangeText: (text: string) => {
                this.altInput = text;
              }
            })
            NumberField({
              label: '方位容差', unit: '°', valueText: this.azTolInput, placeholder: '例如 3',
              onChangeText: (text: string) => {
                this.azTolInput = text;
              }
            })
            NumberField({
              label: '高度容差', unit: '°', valueText: this.altTolInput, placeholder: '例如 3',
              onChangeText: (text: string) => {
                this.altTolInput = text;
              }
            })
            NumberField({
              label: '搜索天数', unit: '天', valueText: this.daysInput, placeholder: '1-365',
              onChangeText: (text: string) => {
                this.daysInput = text;
              }
            })
            Row({ space: Spacing.M }) {
              Text('仅保留白昼（太阳在地平线以上）')
                .fontSize(FontSize.BODY)
                .fontColor($r('app.color.lb_ink'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.daylightOnly })
                .selectedColor($r('app.color.lb_primary'))
                .onChange((on: boolean) => {
                  this.daylightOnly = on;
                })
            }
            .width('100%')
            .constraintSize({ minHeight: MIN_TOUCH })

            Button(this.searching ? '正在搜索…' : '搜索候选时段')
              .type(ButtonType.Normal)
              .width('100%')
              .height(MIN_TOUCH)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_primary'))
              .fontColor($r('app.color.lb_bg'))
              .enabled(!this.searching)
              .onClick(() => {
                this.runSearch();
              })
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          if (this.searching) {
            Row({ space: Spacing.S }) {
              LoadingProgress().width(26).height(26).color($r('app.color.lb_primary'))
              Text('逐日计算中，请稍候…').fontSize(FontSize.BODY).fontColor($r('app.color.lb_muted'))
            }
            .padding(Spacing.L)
          }

          if (this.searched && !this.searching) {
            Column({ space: Spacing.S }) {
              Row({ space: Spacing.S }) {
                Text('候选时段')
                  .fontSize(FontSize.BODY_L)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.lb_ink'))
                  .layoutWeight(1)
                StatusBadge({ label: `${this.candidates.length} 个`, tone: this.candidates.length > 0 ? 1 : 3 })
              }
              .width('100%')
              NoticeBar({ text: this.summary })

              if (this.candidates.length === 0) {
                Text('在该容差与日期范围内没有满足条件的时刻。可以放宽容差、增加天数，或调整目标角。')
                  .fontSize(FontSize.BODY)
                  .fontColor($r('app.color.lb_muted'))
              } else {
                ForEach(this.candidates, (c: Candidate) => {
                  Column({ space: Spacing.S }) {
                    Row({ space: Spacing.S }) {
                      Text(`${TimeUtil.formatDate(this.tzId, c.utcMs)} ${TimeUtil.formatTime(this.tzId, c.utcMs)} · ${TimeUtil.weekdayLabel(TimeUtil.weekday(this.tzId, c.utcMs))}`)
                        .fontSize(FontSize.BODY_L)
                        .fontColor($r('app.color.lb_ink'))
                        .layoutWeight(1)
                      StatusBadge({ label: SolarCalc.phaseLabel(c.phase), tone: c.phase === 5 ? 1 : 2 })
                    }
                    .width('100%')
                    Text(`方位 ${c.azimuth.toFixed(2)}°（误差 ${c.azError.toFixed(2)}°）· 高度 ${c.altitude.toFixed(2)}°（误差 ${c.altError.toFixed(2)}°）`)
                      .fontSize(FontSize.CAPTION)
                      .fontColor($r('app.color.lb_muted'))
                    Button('加入拍摄计划')
                      .type(ButtonType.Normal)
                      .height(MIN_TOUCH)
                      .width('100%')
                      .borderRadius(Radius.BUTTON)
                      .backgroundColor($r('app.color.lb_panel2'))
                      .fontColor($r('app.color.lb_ink'))
                      .onClick(() => {
                        this.addToPlan(c);
                      })
                  }
                  .width('100%')
                  .padding(Spacing.M)
                  .backgroundColor($r('app.color.lb_panel2'))
                  .borderRadius(Radius.BUTTON)
                  .alignItems(HorizontalAlign.Start)
                }, (c: Candidate) => `${c.utcMs}`)
              }
            }
            .width('100%')
            .padding(Spacing.L)
            .backgroundColor($r('app.color.lb_panel'))
            .borderRadius(Radius.CARD)
            .alignItems(HorizontalAlign.Start)
          }
        }
      }
      .width('100%')
      .padding({ bottom: Spacing.XXXL })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }
}
