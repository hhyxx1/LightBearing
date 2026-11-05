import { FontSize, Radius, Spacing, MIN_TOUCH } from '../common/Theme';
import { SunPathChart } from './Charts';

/**
 * 观测仪表（UI-1B-P）：把「当前参数 + 真实高度曲线 + 时间轴 + 时段色带」合并为**一个**观测区域，
 * 不再是「数字卡 + 曲线卡」两张互不相干的通用卡片。
 *
 * 数据全部由调用方传入（真实 SolarCalc / Timeline / lightWindows 结果），本组件不自行计算天文量。
 */
@Component
export struct ObservationPanel {
  @Prop placeName: string = '';
  @Prop tzId: string = 'Asia/Shanghai';
  @Prop lat: number = 0;
  @Prop lon: number = 0;
  @Prop dayStartUtc: number = 0;
  @Prop dayEndUtc: number = 0;
  @Prop selectedUtc: number = 0;
  @Prop sliderProgress: number = 500;
  @Prop posAz: number = 0;
  @Prop posAlt: number = 0;
  @Prop phaseLabel: string = '';
  @Prop phaseShort: string = '';
  @Prop selectedTimeText: string = '--:--';
  @Prop offsetText: string = '';
  @Prop sunriseText: string = '--:--';
  @Prop sunsetText: string = '--:--';
  @Prop goldenPairs: number[] = [];
  @Prop bluePairs: number[] = [];
  @Prop goldenUpper: number = 6;
  @Prop goldenLower: number = -4;
  @Prop blueLower: number = -6;
  @Prop polarText: string = '';
  @Prop chartHeight: number = 200;
  @Prop themeStamp: number = 0;
  onSlide: (progress: number) => void = () => {
  };

  build() {
    Column({ space: Spacing.S }) {
      // 1) 头部：当前光线 + 时刻/偏移 + 阶段
      Row({ space: Spacing.S }) {
        Text('当前光线')
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
          .layoutWeight(1)
        Text(`${this.selectedTimeText} · ${this.offsetText}`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
      }
      .width('100%')

      // 2) 主读数：方位（琥珀）/ 高度（青色）
      Row({ space: Spacing.L }) {
        Column({ space: 2 }) {
          Text(`${this.posAz.toFixed(1)}°`)
            .fontSize(FontSize.DISPLAY)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.lb_primary'))
          Text('方位角')
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.lb_muted'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 2 }) {
          Text(`${this.posAlt.toFixed(1)}°`)
            .fontSize(FontSize.DISPLAY)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.lb_accent'))
          Text('太阳高度角')
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.lb_muted'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 2 }) {
          Text(this.phaseShort.length > 0 ? this.phaseShort : '--')
            .fontSize(FontSize.TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.lb_ink'))
          Text('阶段')
            .fontSize(FontSize.CAPTION)
            .fontColor($r('app.color.lb_muted'))
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      // 3) 真实高度曲线（含地平线、高度刻度、黄金/蓝调色带、当前太阳标记）
      SunPathChart({
        lat: this.lat,
        lon: this.lon,
        tzId: this.tzId,
        dayStartUtc: this.dayStartUtc,
        dayEndUtc: this.dayEndUtc,
        selectedUtc: this.selectedUtc,
        goldenUpper: this.goldenUpper,
        goldenLower: this.goldenLower,
        blueLower: this.blueLower,
        goldenPairs: this.goldenPairs,
        bluePairs: this.bluePairs,
        themeStamp: this.themeStamp,
        chartHeight: this.chartHeight
      })

      // 4) 时间轴：滑块与真实时刻联动
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
          this.onSlide(Math.round(value));
        })
        .accessibilityText('拖动选择今日时刻（真实本地日时间轴，夏令时缺口自动跳过）')

      Row() {
        Text(`${this.sunriseText} 日出`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
        Blank()
        Text(`${this.sunsetText} 日落`)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_muted'))
      }
      .width('100%')

      if (this.polarText.length > 0) {
        Text(this.polarText)
          .fontSize(FontSize.CAPTION)
          .fontColor($r('app.color.lb_primary'))
      }
    }
    .width('100%')
    .padding(Spacing.L)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(HorizontalAlign.Start)
  }
}
