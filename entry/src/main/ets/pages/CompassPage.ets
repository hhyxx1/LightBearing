import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH } from '../common/Theme';
import { Place } from '../model/Models';
import { SolarCalc, SunPosition } from '../services/SolarCalc';
import { TimeUtil } from '../services/TimeUtil';
import { SensorService, CompassReading } from '../services/SensorService';
import { TopBar, EmptyState, ErrorCard, NoticeBar, MetricTile, PermissionGate, Dialogs } from '../components/Widgets';
import { CompassDial } from '../components/Charts';

/**
 * S05 现场罗盘：设备朝向（参考）+ 实时太阳方位 + 误差提示。
 *
 * 传感器只做参考：磁偏角、金属与磁体干扰都会影响读数，
 * 因此提供手动校正量，并明确标注「仅作参考」。
 */
@Component
export struct CompassPage {
  onNavigate: (route: string) => void = () => {
  };
  onBack: () => void = () => {
  };
  @State ready: boolean = false;
  @State errorText: string = '';
  @State hasPlace: boolean = false;
  @State placeName: string = '';
  @State tzId: string = '';
  @State sensorSupported: boolean = true;
  @State listening: boolean = false;
  @State headingDeg: number = -1;
  @State correctionDeg: number = 0;
  @State sunAzimuth: number = 0;
  @State sunAltitude: number = 0;
  @State phaseLabel: string = '';
  @State nowText: string = '--:--';
  @State lastUpdateMs: number = 0;
  @State sensorHint: string = '';

  private timerId: number = -1;

  aboutToAppear(): void {
    this.initPage();
  }

  aboutToDisappear(): void {
    this.stopSensor();
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
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
      this.sensorSupported = await SensorService.hasCompass();
      this.updateSun();
      this.ready = true;
      if (this.sensorSupported) {
        this.startSensor();
      } else {
        this.sensorHint = '当前设备未提供方向传感器。可以改用计算出的太阳方位 + 手机自带指南针应用判断朝向。';
      }
      this.timerId = setInterval(() => {
        this.updateSun();
      }, 30000);
    } catch (err) {
      this.errorText = `初始化失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private updateSun(): void {
    const place = AppState.currentPlace;
    if (place === undefined) {
      return;
    }
    const now = TimeUtil.now();
    const pos: SunPosition = SolarCalc.position(now, place.latWgs84, place.lonWgs84);
    this.sunAzimuth = pos.azimuthDeg;
    this.sunAltitude = pos.altitudeDeg;
    this.phaseLabel = SolarCalc.phaseLabel(SolarCalc.phaseOf(pos.altitudeDeg, AppState.thresholds()));
    this.nowText = TimeUtil.formatTime(place.tzId, now);
  }

  private startSensor(): void {
    const ok = SensorService.start((reading: CompassReading) => {
      this.headingDeg = reading.alphaDeg;
      this.lastUpdateMs = new Date().getTime();
    });
    this.listening = ok;
    if (!ok) {
      this.sensorHint = '传感器订阅失败，可能被系统限制或设备不支持。太阳方位计算仍然可用。';
    }
  }

  private stopSensor(): void {
    SensorService.stop();
    this.listening = false;
  }

  private toggleSensor(): void {
    if (this.listening) {
      this.stopSensor();
    } else {
      this.startSensor();
    }
  }

  private differenceText(): string {
    if (this.headingDeg < 0) {
      return '--';
    }
    const diff = SolarCalc.angularDistance(this.sunAzimuth, this.headingDeg + this.correctionDeg);
    return `${diff.toFixed(0)}°`;
  }

  build() {
    Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({ title: '现场罗盘', subtitle: '设备朝向参考 + 实时太阳方位' })

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
          Text('读取中…').fontSize(FontSize.BODY).fontColor($r('app.color.lb_muted')).padding(Spacing.XXL)
        } else if (!this.hasPlace) {
          EmptyState({
            title: '还没有机位',
            description: '罗盘需要机位坐标来换算太阳方位。请先新增机位。',
            actionLabel: '去机位库',
            onAction: () => {
              this.onNavigate('locations');
            }
          })
        } else {
          Column({ space: Spacing.M }) {
            Row({ space: Spacing.S }) {
              Text(this.placeName)
                .fontSize(FontSize.BODY)
                .fontColor($r('app.color.lb_muted'))
                .layoutWeight(1)
              Text(this.nowText)
                .fontSize(FontSize.CAPTION)
                .fontColor($r('app.color.lb_accent'))
            }
            .width('100%')

            CompassDial({
              sunAzimuth: this.sunAzimuth,
              sunAltitude: this.sunAltitude,
              deviceHeading: this.headingDeg,
              correction: this.correctionDeg,
              dialSize: 280
            })

            Row({ space: Spacing.S }) {
              MetricTile({ valueText: `${this.sunAzimuth.toFixed(1)}°`, labelText: '太阳方位（计算）', highlight: true })
              MetricTile({ valueText: this.headingDeg < 0 ? '--' : `${(this.headingDeg + this.correctionDeg).toFixed(0)}°`,
                labelText: '设备朝向（传感器）' })
              MetricTile({ valueText: this.differenceText(), labelText: '偏差' })
            }
            .width('100%')

            Row({ space: Spacing.S }) {
              Button(this.listening ? '暂停传感器' : '开启传感器')
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .layoutWeight(1)
                .borderRadius(Radius.BUTTON)
                .backgroundColor($r('app.color.lb_panel2'))
                .fontColor($r('app.color.lb_ink'))
                .enabled(this.sensorSupported)
                .onClick(() => {
                  this.toggleSensor();
                })
              Button('校正 -15°')
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .layoutWeight(1)
                .borderRadius(Radius.BUTTON)
                .backgroundColor($r('app.color.lb_panel2'))
                .fontColor($r('app.color.lb_ink'))
                .onClick(() => {
                  this.correctionDeg -= 15;
                })
              Button('校正 +15°')
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .layoutWeight(1)
                .borderRadius(Radius.BUTTON)
                .backgroundColor($r('app.color.lb_panel2'))
                .fontColor($r('app.color.lb_ink'))
                .onClick(() => {
                  this.correctionDeg += 15;
                })
            }
            .width('100%')

            Text(`手动校正量：${this.correctionDeg}°`)
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.lb_muted'))
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Center)

          Row({ space: Spacing.S }) {
            MetricTile({ valueText: `${this.sunAltitude.toFixed(1)}°`, labelText: '太阳高度角' })
            MetricTile({ valueText: this.phaseLabel, labelText: '光线阶段', highlight: true })
            MetricTile({ valueText: `${this.correctionDeg}°`, labelText: '手动校正' })
          }
          .width('100%')

          if (this.sensorHint.length > 0) {
            NoticeBar({ text: this.sensorHint })
          }

          if (!this.sensorSupported) {
            PermissionGate({
              title: '该设备没有可用方向传感器',
              reason: '逐光不会伪造朝向读数。你可以用计算出的太阳方位配合外部指南针判断机位朝向，或改用地图页的方位图。',
              grantLabel: '去地图方位图',
              fallbackLabel: '返回首页',
              onGrant: () => {
                this.onNavigate('map');
              },
              onFallback: () => {
                this.onBack();
              }
            })
          }

          NoticeBar({
            text: '传感器读数仅作参考：磁偏角（中国东部约 -5° 到 -6°）、附近金属与磁体都会造成偏差；如需精确朝向，请用外部指南针校准后再校正本条。'
          })

          Button('按当前时刻保存计划')
            .type(ButtonType.Normal)
            .width('100%')
            .height(MIN_TOUCH)
            .borderRadius(Radius.BUTTON)
            .backgroundColor($r('app.color.lb_primary'))
            .fontColor($r('app.color.lb_bg'))
            .onClick(() => {
              const place: Place | undefined = AppState.currentPlace;
              if (place === undefined) {
                return;
              }
              const pos = SolarCalc.position(TimeUtil.now(), place.latWgs84, place.lonWgs84);
              Dialogs.toast(this.getUIContext(),
                `当前太阳方位 ${pos.azimuthDeg.toFixed(0)}°，高度 ${pos.altitudeDeg.toFixed(0)}°（可在拍摄计划中保存）`);
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
