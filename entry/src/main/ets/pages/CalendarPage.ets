import { common } from '@kit.AbilityKit';
import { componentSnapshot } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH, ThemeColors } from '../common/Theme';
import { Place, ShootPlan } from '../model/Models';
import { SolarCalc, SolarEvents, LightWindow } from '../services/SolarCalc';
import { TimeUtil } from '../services/TimeUtil';
import { ExportService, ExportResult } from '../services/ExportService';
import { TopBar, EmptyState, ErrorCard, NoticeBar, StatusBadge, SkeletonCard, Dialogs } from '../components/Widgets';

/** 月历单元格 */
class DayCell {
  dayOfMonth: number = 0;
  dayStartUtc: number = 0;
  inMonth: boolean = true;
  hasGolden: boolean = false;
  planCount: number = 0;
  sunriseText: string = '--:--';
  sunsetText: string = '--:--';
  goldenAm: string = '无';
  goldenPm: string = '无';
  solarNoonText: string = '--:--';
  polarState: number = 0;
}

/**
 * S08 日历：月历阳光窗口、计划日期筛选、分享计划卡片。
 * 每天窗口都由真实经纬度与日期现算，不是固定模板。
 */
@Component
export struct CalendarPage {
  onNavigate: (route: string) => void = () => {
  };
  onBack: () => void = () => {
  };
  @State ready: boolean = false;
  @State errorText: string = '';
  @State hasPlace: boolean = false;
  @State placeName: string = '';
  @State tzId: string = '';
  @State year: number = 2026;
  @State month: number = 1;
  @State cells: DayCell[] = [];
  @State selectedIndex: number = 0;
  @State selectedSummary: string = '';
  @State selectedGoldenAm: string = '无';
  @State selectedGoldenPm: string = '无';
  @State selectedPlans: ShootPlan[] = [];
  @State hint: string = '';
  @State exporting: boolean = false;
  @State colors: ThemeColors = new ThemeColors();

  aboutToAppear(): void {
    this.initPage();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async initPage(): Promise<void> {
    try {
      this.errorText = '';
      await AppState.bootstrap(this.hostContext());
      this.colors = ThemeColors.load(this.hostContext());
      const place = AppState.currentPlace;
      if (place === undefined) {
        this.hasPlace = false;
        this.ready = true;
        return;
      }
      this.hasPlace = true;
      this.placeName = place.name;
      this.tzId = place.tzId;
      const local = TimeUtil.toLocal(place.tzId, TimeUtil.now());
      this.year = local.year;
      this.month = local.month;
      this.buildMonth();
      this.ready = true;
    } catch (err) {
      this.errorText = `初始化失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private buildMonth(): void {
    const place = AppState.currentPlace;
    if (place === undefined) {
      return;
    }
    const cells: DayCell[] = [];
    const firstUtc = TimeUtil.fromLocal(place.tzId, this.year, this.month, 1, 0, 0);
    const firstWeekday = TimeUtil.weekday(place.tzId, firstUtc);
    const daysInMonth = new Date(this.year, this.month, 0).getDate();
    // 前置空位（周一为首列：周日→6）
    const leading = (firstWeekday + 6) % 7;
    for (let i = 0; i < leading; i++) {
      const pad = new DayCell();
      pad.inMonth = false;
      cells.push(pad);
    }
    for (let day = 1; day <= daysInMonth; day++) {
      const cell = new DayCell();
      cell.dayOfMonth = day;
      cell.inMonth = true;
      cell.dayStartUtc = TimeUtil.fromLocal(place.tzId, this.year, this.month, day, 0, 0);
      const ev: SolarEvents = SolarCalc.events(cell.dayStartUtc, place.latWgs84, place.lonWgs84);
      const w: LightWindow = SolarCalc.lightWindows(cell.dayStartUtc, place.latWgs84, place.lonWgs84,
        AppState.thresholds());
      cell.polarState = ev.polarState;
      cell.sunriseText = ev.sunriseUtc < 0 ? '无' : TimeUtil.formatTime(place.tzId, ev.sunriseUtc);
      cell.sunsetText = ev.sunsetUtc < 0 ? '无' : TimeUtil.formatTime(place.tzId, ev.sunsetUtc);
      cell.solarNoonText = TimeUtil.formatTime(place.tzId, ev.solarNoonUtc);
      cell.goldenAm = w.goldenMorningStartUtc < 0 ? '无'
        : `${TimeUtil.formatTime(place.tzId, w.goldenMorningStartUtc)}-${TimeUtil.formatTime(place.tzId, w.goldenMorningEndUtc)}`;
      cell.goldenPm = w.goldenEveningStartUtc < 0 ? '无'
        : `${TimeUtil.formatTime(place.tzId, w.goldenEveningStartUtc)}-${TimeUtil.formatTime(place.tzId, w.goldenEveningEndUtc)}`;
      cell.hasGolden = w.goldenMorningStartUtc >= 0 || w.goldenEveningStartUtc >= 0;
      let count = 0;
      for (const plan of AppState.plans) {
        const planLocal = TimeUtil.toLocal(place.tzId, plan.selectedUtc);
        if (planLocal.year === this.year && planLocal.month === this.month && planLocal.day === day) {
          count++;
        }
      }
      cell.planCount = count;
      cells.push(cell);
    }
    this.cells = cells;
    if (this.selectedIndex >= cells.length || !cells[this.selectedIndex].inMonth) {
      this.selectedIndex = leading;
    }
    this.selectDay(this.selectedIndex);
  }

  private selectDay(index: number): void {
    if (index < 0 || index >= this.cells.length) {
      return;
    }
    const cell = this.cells[index];
    if (!cell.inMonth) {
      return;
    }
    this.selectedIndex = index;
    this.selectedGoldenAm = cell.goldenAm;
    this.selectedGoldenPm = cell.goldenPm;
    this.selectedSummary = `${this.year}-${String(this.month).padStart(2, '0')}-${String(cell.dayOfMonth).padStart(2, '0')} · 日出 ${cell.sunriseText} · 日落 ${cell.sunsetText} · 正午 ${cell.solarNoonText}`;
    const plans: ShootPlan[] = [];
    const place = AppState.currentPlace;
    if (place !== undefined) {
      for (const plan of AppState.plans) {
        const planLocal = TimeUtil.toLocal(place.tzId, plan.selectedUtc);
        if (planLocal.year === this.year && planLocal.month === this.month && planLocal.day === cell.dayOfMonth) {
          plans.push(plan);
        }
      }
    }
    this.selectedPlans = plans;
  }

  private shiftMonth(delta: number): void {
    let m = this.month + delta;
    let y = this.year;
    if (m < 1) {
      m = 12;
      y -= 1;
    } else if (m > 12) {
      m = 1;
      y += 1;
    }
    this.month = m;
    this.year = y;
    this.buildMonth();
  }

  private async exportPng(): Promise<void> {
    this.exporting = true;
    this.hint = '';
    try {
      const pixelMap: image.PixelMap = await this.getUIContext().getComponentSnapshot().get('shareCard');
      const fileName = `lightbearing-${this.year}-${String(this.month).padStart(2, '0')}-${this.selectedDay()}.png`;
      const result: ExportResult = await ExportService.exportPng(this.hostContext(), fileName, pixelMap);
      if (result.ok) {
        await ExportService.recordAsset(result, AppState.currentProjectId);
      }
      this.hint = result.ok ? `已导出 PNG（${result.bytes} 字节）：${result.uri}` : result.message;
      await pixelMap.release();
    } catch (err) {
      this.hint = `导出 PNG 失败：${(err as Error).message}`;
    } finally {
      this.exporting = false;
    }
  }

  private selectedDay(): number {
    if (this.selectedIndex >= 0 && this.selectedIndex < this.cells.length) {
      return this.cells[this.selectedIndex].dayOfMonth;
    }
    return 1;
  }

  private async exportCsv(): Promise<void> {
    this.exporting = true;
    try {
      const rows: string[][] = [];
      rows.push(['日期', '日出', '日落', '太阳正午', '黄金时刻(晨)', '黄金时刻(夕)', '计划数', '极昼极夜']);
      for (const cell of this.cells) {
        if (!cell.inMonth) {
          continue;
        }
        rows.push([`${this.year}-${String(this.month).padStart(2, '0')}-${String(cell.dayOfMonth).padStart(2, '0')}`,
          cell.sunriseText, cell.sunsetText, cell.solarNoonText, cell.goldenAm, cell.goldenPm,
          `${cell.planCount}`, cell.polarState === 0 ? '正常' : (cell.polarState === 1 ? '极昼' : '极夜')]);
      }
      const result = await ExportService.exportCsv(this.hostContext(),
        `lightbearing-${this.year}-${String(this.month).padStart(2, '0')}.csv`, rows);
      if (result.ok) {
        await ExportService.recordAsset(result, AppState.currentProjectId);
      }
      this.hint = result.ok ? `已导出 CSV（${result.bytes} 字节）：${result.uri}` : result.message;
    } catch (err) {
      this.hint = `导出 CSV 失败：${(err as Error).message}`;
    } finally {
      this.exporting = false;
    }
  }

  @Builder
  shareCard() {
    Column({ space: Spacing.S }) {
      Row() {
        Text('逐光 · 拍摄计划卡片')
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_primary'))
          .layoutWeight(1)
        Text(`${this.year}-${String(this.month).padStart(2, '0')}`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
      }
      .width('100%')

      Text(this.placeName)
        .fontSize(FontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.lb_ink'))
        .width('100%')
      Text(this.selectedSummary)
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_muted'))
        .width('100%')
      Text(`黄金时刻：晨 ${this.selectedGoldenAm} / 夕 ${this.selectedGoldenPm}`)
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_accent'))
        .width('100%')
      if (this.selectedPlans.length > 0) {
        Text(`当日计划 ${this.selectedPlans.length} 条：${this.selectedPlans[0].placeName} ${TimeUtil.formatTime(this.selectedPlans[0].tzId, this.selectedPlans[0].selectedUtc)}`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_ink'))
          .width('100%')
      }
      Text('算法：NOAA/Meeus · 日出日落几何高度 -0.833° · 数据由本机实时计算')
        .fontSize(FontSize.CAPTION)
        .fontColor($r('app.color.lb_muted'))
        .width('100%')
    }
    .id('shareCard')
    .width('100%')
    .padding(Spacing.XL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .alignItems(HorizontalAlign.Start)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
  }

  build() {
    Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({ title: '日历', subtitle: '月历阳光窗口与计划日期' })

        if (this.errorText.length > 0) {
          ErrorCard({
            message: this.errorText,
            onRetry: () => {
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
            description: '日历按机位坐标计算每天的阳光窗口。请先新增机位。',
            actionLabel: '去机位库',
            onAction: () => {
              this.onNavigate('locations');
            }
          })
        } else {
          Row({ space: Spacing.S }) {
            Button('上月')
              .type(ButtonType.Normal)
              .height(MIN_TOUCH)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_panel2'))
              .fontColor($r('app.color.lb_ink'))
              .onClick(() => {
                this.shiftMonth(-1);
              })
            Text(`${this.year} 年 ${this.month} 月`)
              .fontSize(FontSize.BODY_L)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.lb_ink'))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Button('下月')
              .type(ButtonType.Normal)
              .height(MIN_TOUCH)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_panel2'))
              .fontColor($r('app.color.lb_ink'))
              .onClick(() => {
                this.shiftMonth(1);
              })
          }
          .width('100%')

          Column({ space: Spacing.S }) {
            Row() {
              ForEach(['一', '二', '三', '四', '五', '六', '日'], (label: string) => {
                Text(label)
                  .fontSize(FontSize.CAPTION)
                  .fontColor($r('app.color.lb_muted'))
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
              }, (label: string) => label)
            }
            .width('100%')

            Grid() {
              ForEach(this.cells, (cell: DayCell, index: number) => {
                GridItem() {
                  Column({ space: 2 }) {
                    Text(cell.inMonth ? `${cell.dayOfMonth}` : '')
                      .fontSize(FontSize.BODY)
                      .fontColor(cell.inMonth
                        ? (index === this.selectedIndex ? $r('app.color.lb_bg') : $r('app.color.lb_ink'))
                        : $r('app.color.lb_line'))
                    if (cell.inMonth) {
                      Row({ space: 2 }) {
                        if (cell.hasGolden) {
                          Circle({ width: 5, height: 5 }).fill($r('app.color.lb_primary'))
                        }
                        if (cell.planCount > 0) {
                          Circle({ width: 5, height: 5 }).fill($r('app.color.lb_accent'))
                        }
                        if (cell.polarState !== 0) {
                          Circle({ width: 5, height: 5 }).fill($r('app.color.lb_muted'))
                        }
                      }
                    }
                  }
                  .width('100%')
                  .height(46)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(index === this.selectedIndex && cell.inMonth
                    ? $r('app.color.lb_primary') : Color.Transparent)
                  .borderRadius(Radius.BUTTON)
                  .accessibilityText(cell.inMonth
                    ? `${cell.dayOfMonth} 日，${cell.hasGolden ? '有黄金时刻，' : ''}${cell.planCount > 0 ? `计划 ${cell.planCount} 条` : '无计划'}`
                    : '空白')
                  .onClick(() => {
                    this.selectDay(index);
                  })
                }
              }, (cell: DayCell, index: number) => `${cell.dayStartUtc}_${index}`)
            }
            .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
            .width('100%')
            .height(Math.ceil(this.cells.length / 7) * 52)
            .scrollBar(BarState.Off)

            Row({ space: Spacing.S }) {
              Row({ space: 4 }) {
                Circle({ width: 5, height: 5 }).fill($r('app.color.lb_primary'))
                Text('有黄金时刻').fontSize(FontSize.CAPTION).fontColor($r('app.color.lb_muted'))
              }
              Row({ space: 4 }) {
                Circle({ width: 5, height: 5 }).fill($r('app.color.lb_accent'))
                Text('有计划').fontSize(FontSize.CAPTION).fontColor($r('app.color.lb_muted'))
              }
            }
            .width('100%')
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          Column({ space: Spacing.S }) {
            Text(this.selectedSummary)
              .fontSize(FontSize.BODY)
              .fontColor($r('app.color.lb_ink'))
            Text(`黄金时刻：晨 ${this.selectedGoldenAm} · 夕 ${this.selectedGoldenPm}`)
              .fontSize(FontSize.BODY)
              .fontColor($r('app.color.lb_accent'))
            if (this.selectedPlans.length > 0) {
              ForEach(this.selectedPlans, (plan: ShootPlan) => {
                Text(`· ${plan.placeName} ${TimeUtil.formatTime(plan.tzId, plan.selectedUtc)} 目标 ${plan.targetAzimuth.toFixed(0)}°`)
                  .fontSize(FontSize.CAPTION)
                  .fontColor($r('app.color.lb_muted'))
              }, (plan: ShootPlan) => plan.id)
            } else {
              Text('当日没有计划。')
                .fontSize(FontSize.CAPTION)
                .fontColor($r('app.color.lb_muted'))
            }
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          this.shareCard()

          Row({ space: Spacing.S }) {
            Button(this.exporting ? '导出中…' : '导出卡片 PNG')
              .type(ButtonType.Normal)
              .height(MIN_TOUCH)
              .layoutWeight(1)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_primary'))
              .fontColor($r('app.color.lb_bg'))
              .enabled(!this.exporting)
              .onClick(() => {
                this.exportPng();
              })
            Button('导出本月 CSV')
              .type(ButtonType.Normal)
              .height(MIN_TOUCH)
              .layoutWeight(1)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_panel2'))
              .fontColor($r('app.color.lb_ink'))
              .enabled(!this.exporting)
              .onClick(() => {
                this.exportCsv();
              })
          }
          .width('100%')

          if (this.hint.length > 0) {
            NoticeBar({ text: this.hint })
          }

          NoticeBar({
            text: '导出使用系统文件保存面板，返回的 URI 由系统签发，可在文件管理器中独立打开验证；逐光不会用「导出成功」的提示替代真实写文件。'
          })
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
