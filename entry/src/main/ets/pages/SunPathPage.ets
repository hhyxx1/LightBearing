import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH } from '../common/Theme';
import { Place, ShootPlan, IdGen } from '../model/Models';
import { SolarCalc, SunPosition, SolarEvents, LightPhase, LightWindow } from '../services/SolarCalc';
import { TimeUtil } from '../services/TimeUtil';
import { AppDb } from '../repository/AppDb';
import { TopBar, EmptyState, ErrorCard, NoticeBar, MetricTile, SectionCard, Dialogs } from '../components/Widgets';
import { SunPathChart, CompassDial } from '../components/Charts';

/**
 * S02 太阳轨迹：任意日期的日轨、全天时刻拖动、日出日落与方向辅助。
 */
@Component
export struct SunPathPage {
  onNavigate: (route: string) => void = () => {
  };
  onBack: () => void = () => {
  };
  @State ready: boolean = false;
  @State errorText: string = '';
  @State hasPlace: boolean = false;
  @State tzId: string = '';
  @State placeName: string = '';
  @State dayStartUtc: number = 0;
  @State selectedUtc: number = 0;
  @State sliderMinutes: number = 720;
  @State azText: string = '--';
  @State altText: string = '--';
  @State phaseLabel: string = '';
  @State sunriseText: string = '--:--';
  @State sunsetText: string = '--:--';
  @State noonText: string = '--:--';
  @State noonAltText: string = '--';
  @State polarText: string = '';
  @State pickedDate: Date = new Date();

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
      this.dayStartUtc = TimeUtil.startOfLocalDay(place.tzId, TimeUtil.now());
      this.syncPickedDate();
      this.sliderMinutes = 720;
      this.applyTime(12, 0);
      this.ready = true;
    } catch (err) {
      this.errorText = `读取机位失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private syncPickedDate(): void {
    const local = TimeUtil.toLocal(this.tzId, this.dayStartUtc);
    this.pickedDate = new Date(local.year, local.month - 1, local.day);
  }

  private applyTime(hour: number, minute: number): void {
    const place = AppState.currentPlace;
    if (place === undefined) {
      return;
    }
    const local = TimeUtil.toLocal(place.tzId, this.dayStartUtc);
    this.selectedUtc = TimeUtil.fromLocal(place.tzId, local.year, local.month, local.day, hour, minute);
    const pos: SunPosition = SolarCalc.position(this.selectedUtc, place.latWgs84, place.lonWgs84);
    this.azText = `${pos.azimuthDeg.toFixed(1)}°`;
    this.altText = `${pos.altitudeDeg.toFixed(1)}°`;
    this.phaseLabel = SolarCalc.phaseLabel(SolarCalc.phaseOf(pos.altitudeDeg, AppState.thresholds()));

    const ev: SolarEvents = SolarCalc.events(this.dayStartUtc, place.latWgs84, place.lonWgs84);
    this.sunriseText = ev.sunriseUtc < 0 ? '无' : TimeUtil.formatTime(place.tzId, ev.sunriseUtc);
    this.sunsetText = ev.sunsetUtc < 0 ? '无' : TimeUtil.formatTime(place.tzId, ev.sunsetUtc);
    this.noonText = TimeUtil.formatTime(place.tzId, ev.solarNoonUtc);
    this.noonAltText = `${ev.noonAltitudeDeg.toFixed(1)}°`;
    if (ev.polarState === 1) {
      this.polarText = '当日极昼：太阳全天不落，黄金时刻以高度角阈值直接给出。';
    } else if (ev.polarState === 2) {
      this.polarText = '当日极夜：太阳全天不升，无黄金/蓝调窗口。';
    } else {
      this.polarText = '';
    }
  }

  private changeDay(deltaDays: number): void {
    this.dayStartUtc = TimeUtil.addLocalDays(this.tzId, this.dayStartUtc, deltaDays);
    this.syncPickedDate();
    this.applyTime(Math.floor(this.sliderMinutes / 60), Math.round(this.sliderMinutes % 60));
  }

  private onSlider(minutes: number): void {
    this.sliderMinutes = minutes;
    this.applyTime(Math.floor(minutes / 60), Math.round(minutes % 60));
  }

  private async saveAsPlan(): Promise<void> {
    const place = AppState.currentPlace;
    if (place === undefined) {
      return;
    }
    try {
      const pos = SolarCalc.position(this.selectedUtc, place.latWgs84, place.lonWgs84);
      const plan = new ShootPlan();
      plan.id = IdGen.next('s');
      plan.placeId = place.id;
      plan.placeName = place.name;
      plan.latWgs84 = place.latWgs84;
      plan.lonWgs84 = place.lonWgs84;
      plan.tzId = place.tzId;
      plan.selectedUtc = this.selectedUtc;
      plan.targetAzimuth = pos.azimuthDeg;
      plan.targetAltitude = pos.altitudeDeg;
      plan.azTolerance = 3;
      plan.altTolerance = 3;
      plan.note = `来自太阳轨迹 ${TimeUtil.formatTime(place.tzId, this.selectedUtc)}`;
      plan.checklist = '[]';
      await AppDb.savePlan(plan, `从太阳轨迹保存计划 · ${place.name}`);
      await AppState.reloadData();
      Dialogs.toast(this.getUIContext(), '已保存到拍摄计划');
    } catch (err) {
      Dialogs.toast(this.getUIContext(), `保存失败：${(err as Error).message}`);
    }
  }

  @Builder
  controls() {
    Column({ space: Spacing.M }) {
      Row({ space: Spacing.S }) {
        Button('前一天')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_panel2'))
          .fontColor($r('app.color.lb_ink'))
          .onClick(() => {
            this.changeDay(-1);
          })
        Button('今天')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_panel2'))
          .fontColor($r('app.color.lb_ink'))
          .onClick(() => {
            const place = AppState.currentPlace;
            if (place !== undefined) {
              this.dayStartUtc = TimeUtil.startOfLocalDay(place.tzId, TimeUtil.now());
              this.syncPickedDate();
              this.applyTime(Math.floor(this.sliderMinutes / 60), Math.round(this.sliderMinutes % 60));
            }
          })
        Button('后一天')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_panel2'))
          .fontColor($r('app.color.lb_ink'))
          .onClick(() => {
            this.changeDay(1);
          })
      }
      .width('100%')

      DatePicker({
        start: new Date(2000, 0, 1),
        end: new Date(2100, 11, 31),
        selected: this.pickedDate
      })
        .onDateChange((value: Date) => {
          this.dayStartUtc = TimeUtil.fromLocal(this.tzId, value.getFullYear(), value.getMonth() + 1, value.getDate(), 0, 0);
          this.pickedDate = value;
          this.applyTime(Math.floor(this.sliderMinutes / 60), Math.round(this.sliderMinutes % 60));
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

  build() {
    Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({ title: '太阳轨迹', subtitle: '全天日轨、地平线与时刻拖动' })

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
          Row({ space: Spacing.S }) {
            LoadingProgress().width(28).height(28).color($r('app.color.lb_primary'))
            Text('计算中…').fontSize(FontSize.BODY).fontColor($r('app.color.lb_muted'))
          }
          .padding(Spacing.XXL)
        } else if (!this.hasPlace) {
          EmptyState({
            title: '还没有机位',
            description: '太阳轨迹需要机位经纬度。请先到机位库新增一个机位。',
            actionLabel: '去新增机位',
            onAction: () => {
              this.onNavigate('locations');
            }
          })
        } else {
          this.controls()

          Column({ space: Spacing.S }) {
            Text(this.placeName)
              .fontSize(FontSize.BODY)
              .fontColor($r('app.color.lb_muted'))
            SunPathChart({
              lat: AppState.currentPlace === undefined ? 0 : AppState.currentPlace.latWgs84,
              lon: AppState.currentPlace === undefined ? 0 : AppState.currentPlace.lonWgs84,
              tzId: this.tzId,
              dayStartUtc: this.dayStartUtc,
              selectedUtc: this.selectedUtc,
              goldenUpper: AppState.settings.goldenUpper,
              goldenLower: AppState.settings.goldenLower,
              blueLower: AppState.settings.blueLower,
              chartHeight: 230
            })
            Slider({ value: this.sliderMinutes, min: 0, max: 1439, step: 1 })
              .selectedColor($r('app.color.lb_primary'))
              .trackColor($r('app.color.lb_panel2'))
              .blockColor($r('app.color.lb_primary'))
              .width('100%')
              .onChange((value: number) => {
                this.onSlider(Math.round(value));
              })
              .accessibilityText('拖动选择时刻')
            Text(`选定 ${TimeUtil.formatTime(this.tzId, this.selectedUtc)} · ${this.phaseLabel}`)
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.lb_accent'))
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          Row({ space: Spacing.S }) {
            MetricTile({ valueText: this.azText, labelText: '方位角', highlight: true })
            MetricTile({ valueText: this.altText, labelText: '高度角' })
            MetricTile({ valueText: this.phaseLabel, labelText: '光线阶段' })
          }
          .width('100%')

          Row({ space: Spacing.S }) {
            MetricTile({ valueText: this.sunriseText, labelText: '日出' })
            MetricTile({ valueText: this.noonText, labelText: '太阳正午' })
            MetricTile({ valueText: this.sunsetText, labelText: '日落' })
          }
          .width('100%')

          Row({ space: Spacing.S }) {
            MetricTile({ valueText: this.noonAltText, labelText: '正午高度角' })
            MetricTile({ valueText: TimeUtil.offsetLabel(this.tzId, this.dayStartUtc), labelText: '时区偏移' })
          }
          .width('100%')

          if (this.polarText.length > 0) {
            NoticeBar({ text: this.polarText })
          }

          Column({ space: Spacing.M }) {
            Text('方向辅助')
              .fontSize(FontSize.BODY_L)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.lb_ink'))
            CompassDial({
              sunAzimuth: AppState.currentPlace === undefined ? 0
                : SolarCalc.position(this.selectedUtc, AppState.currentPlace.latWgs84, AppState.currentPlace.lonWgs84).azimuthDeg,
              sunAltitude: AppState.currentPlace === undefined ? 0
                : SolarCalc.position(this.selectedUtc, AppState.currentPlace.latWgs84, AppState.currentPlace.lonWgs84).altitudeDeg,
              deviceHeading: SolarCalc.position(this.selectedUtc, AppState.currentPlace === undefined ? 0 : AppState.currentPlace.latWgs84,
                AppState.currentPlace === undefined ? 0 : AppState.currentPlace.lonWgs84).azimuthDeg,
              correction: 0,
              dialSize: 240
            })
            Text('金色指针为太阳方位；此处不使用传感器，仅作为计算结果的方位提示。现场实测请到「现场罗盘」。')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.lb_muted'))
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Center)

          Button('把此刻存为拍摄计划')
            .type(ButtonType.Normal)
            .width('100%')
            .height(MIN_TOUCH)
            .borderRadius(Radius.BUTTON)
            .backgroundColor($r('app.color.lb_primary'))
            .fontColor($r('app.color.lb_bg'))
            .onClick(() => {
              this.saveAsPlan();
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
