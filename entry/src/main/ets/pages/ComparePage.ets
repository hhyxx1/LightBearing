import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH, ThemeColors } from '../common/Theme';
import { Place } from '../model/Models';
import { SolarCalc, SunPosition } from '../services/SolarCalc';
import { TimeUtil } from '../services/TimeUtil';
import { AppDb } from '../repository/AppDb';
import { TopBar, EmptyState, ErrorCard, NoticeBar, StatusBadge, Dialogs } from '../components/Widgets';
import { CompareChart, CompareSeries } from '../components/Charts';

/** 对照行：某本地时刻在某日期的方位/高度 */
class CompareRow {
  label: string = '';
  cells: string[] = [];
}

/**
 * S09 时间比较：多日期方位/高度对照与同日时段曲线（真实算法）。
 */
@Component
export struct ComparePage {
  onNavigate: (route: string) => void = () => {
  };
  onBack: () => void = () => {
  };
  @State ready: boolean = false;
  @State errorText: string = '';
  @State hasPlace: boolean = false;
  @State placeName: string = '';
  @State tzId: string = '';
  @State dates: string[] = [];
  @State rows: CompareRow[] = [];
  @State seriesToken: number = 0;
  @State hint: string = '';
  @State pickedDate: Date = new Date();
  @State colors: ThemeColors = new ThemeColors();
  private series: CompareSeries[] = [];

  aboutToAppear(): void {
    this.initPage();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async initPage(): Promise<void> {
    try {
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
      this.pickedDate = new Date(local.year, local.month - 1, local.day);
      this.dates = [`${local.year}-${String(local.month).padStart(2, '0')}-${String(local.day).padStart(2, '0')}`];
      this.rebuild();
      this.ready = true;
    } catch (err) {
      this.errorText = `初始化失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private addPickedDate(): void {
    const place = AppState.currentPlace;
    if (place === undefined) {
      return;
    }
    const label = `${this.pickedDate.getFullYear()}-${String(this.pickedDate.getMonth() + 1).padStart(2, '0')}-${String(this.pickedDate.getDate()).padStart(2, '0')}`;
    for (const existing of this.dates) {
      if (existing === label) {
        this.hint = `${label} 已在对照列表中。`;
        return;
      }
    }
    if (this.dates.length >= 5) {
      this.hint = '最多同时对照 5 个日期。';
      return;
    }
    this.dates.push(label);
    this.hint = `已加入 ${label}`;
    this.rebuild();
  }

  private removeDate(label: string): void {
    const next: string[] = [];
    for (const d of this.dates) {
      if (d !== label) {
        next.push(d);
      }
    }
    this.dates = next;
    this.rebuild();
  }

  private rebuild(): void {
    const place = AppState.currentPlace;
    if (place === undefined) {
      return;
    }
    const labels: string[] = ['06:00', '09:00', '12:00', '15:00', '18:00'];
    const hours: number[] = [6, 9, 12, 15, 18];
    const rows: CompareRow[] = [];
    for (let i = 0; i < labels.length; i++) {
      const row = new CompareRow();
      row.label = labels[i];
      const cells: string[] = [];
      for (const dateLabel of this.dates) {
        const parts: string[] = dateLabel.split('-');
        if (parts.length < 3) {
          continue;
        }
        const utc = TimeUtil.fromLocal(place.tzId, Number.parseInt(parts[0]), Number.parseInt(parts[1]),
          Number.parseInt(parts[2]), hours[i], 0);
        const pos: SunPosition = SolarCalc.position(utc, place.latWgs84, place.lonWgs84);
        cells.push(`${pos.azimuthDeg.toFixed(0)}° / ${pos.altitudeDeg.toFixed(0)}°`);
      }
      row.cells = cells;
      rows.push(row);
    }
    this.rows = rows;

    const palette: string[] = [this.colors.primary, this.colors.accent, '#E48A8A', '#9CCB7A', '#B49CE0'];
    const series: CompareSeries[] = [];
    for (let i = 0; i < this.dates.length; i++) {
      const parts: string[] = this.dates[i].split('-');
      if (parts.length < 3) {
        continue;
      }
      const s = new CompareSeries();
      s.label = this.dates[i];
      s.colorHex = palette[i % palette.length];
      s.lat = place.latWgs84;
      s.lon = place.lonWgs84;
      s.tzId = place.tzId;
      s.dayStartUtc = TimeUtil.fromLocal(place.tzId, Number.parseInt(parts[0]), Number.parseInt(parts[1]),
        Number.parseInt(parts[2]), 0, 0);
      series.push(s);
    }
    this.series = series;
    this.seriesToken = this.seriesToken + 1;
  }

  private async saveHistory(): Promise<void> {
    try {
      await AppDb.addHistory('compare', `时间对照 ${this.placeName} ${this.dates.length} 个日期`, this.dates.join(','));
      Dialogs.toast(this.getUIContext(), '已记录到历史');
    } catch (err) {
      this.hint = `写入历史失败：${(err as Error).message}`;
    }
  }

  build() {
    Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({ title: '时间比较', subtitle: '多日期方位/高度对照' })

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
          Text('计算中…').fontSize(FontSize.BODY).fontColor($r('app.color.lb_muted')).padding(Spacing.XXL)
        } else if (!this.hasPlace) {
          EmptyState({
            title: '还没有机位',
            description: '时间比较使用同一机位在不同日期的太阳方位。请先新增机位。',
            actionLabel: '去机位库',
            onAction: () => {
              this.onNavigate('locations');
            }
          })
        } else {
          Column({ space: Spacing.M }) {
            Text(this.placeName)
              .fontSize(FontSize.BODY)
              .fontColor($r('app.color.lb_muted'))
            DatePicker({
              start: new Date(2000, 0, 1),
              end: new Date(2100, 11, 31),
              selected: this.pickedDate
            })
              .onDateChange((value: Date) => {
                this.pickedDate = value;
              })
            Button('加入对照日期')
              .type(ButtonType.Normal)
              .width('100%')
              .height(MIN_TOUCH)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_primary'))
              .fontColor($r('app.color.lb_bg'))
              .onClick(() => {
                this.addPickedDate();
              })
            if (this.hint.length > 0) {
              NoticeBar({ text: this.hint })
            }
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          Column({ space: Spacing.S }) {
            Text('对照日期')
              .fontSize(FontSize.BODY_L)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.lb_ink'))
            ForEach(this.dates, (label: string, index: number) => {
              Row({ space: Spacing.S }) {
                Circle({ width: 10, height: 10 })
                  .fill(index === 0 ? $r('app.color.lb_primary') : (index === 1 ? $r('app.color.lb_accent') : $r('app.color.lb_muted')))
                Text(label)
                  .fontSize(FontSize.BODY)
                  .fontColor($r('app.color.lb_ink'))
                  .layoutWeight(1)
                Button('移除')
                  .type(ButtonType.Normal)
                  .height(32)
                  .fontSize(FontSize.CAPTION)
                  .borderRadius(Radius.BUTTON)
                  .backgroundColor($r('app.color.lb_panel2'))
                  .fontColor($r('app.color.lb_muted'))
                  .onClick(() => {
                    this.removeDate(label);
                  })
              }
              .width('100%')
              .constraintSize({ minHeight: MIN_TOUCH })
            }, (label: string) => label)
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          Column({ space: Spacing.S }) {
            Text('同日时段曲线')
              .fontSize(FontSize.BODY_L)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.lb_ink'))
            CompareChart({ seriesToken: this.seriesToken, series: this.series, chartHeight: 240 })
            Text('横轴为本地时间 0-24 时，纵轴为太阳高度角；每条曲线对应一个对照日期。')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.lb_muted'))
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          Column({ space: Spacing.S }) {
            Text('时刻对照（方位 / 高度）')
              .fontSize(FontSize.BODY_L)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.lb_ink'))
            ForEach(this.rows, (row: CompareRow) => {
              Row({ space: Spacing.S }) {
                Text(row.label)
                  .fontSize(FontSize.CAPTION)
                  .fontColor($r('app.color.lb_muted'))
                  .width(46)
                ForEach(row.cells, (cell: string) => {
                  Text(cell)
                    .fontSize(FontSize.CAPTION)
                    .fontColor($r('app.color.lb_ink'))
                    .layoutWeight(1)
                    .textAlign(TextAlign.Center)
                }, (cell: string, index: number) => `${row.label}_${index}_${cell}`)
              }
              .width('100%')
              .constraintSize({ minHeight: 32 })
            }, (row: CompareRow) => row.label)
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          Button('记录本次对照')
            .type(ButtonType.Normal)
            .width('100%')
            .height(MIN_TOUCH)
            .borderRadius(Radius.BUTTON)
            .backgroundColor($r('app.color.lb_panel2'))
            .fontColor($r('app.color.lb_ink'))
            .onClick(() => {
              this.saveHistory();
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
