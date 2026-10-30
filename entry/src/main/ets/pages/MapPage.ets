import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH } from '../common/Theme';
import { Place } from '../model/Models';
import { SolarCalc, SunPosition } from '../services/SolarCalc';
import { TimeUtil } from '../services/TimeUtil';
import { TopBar, EmptyState, ErrorCard, NoticeBar, NumberField, StatusBadge, SkeletonCard, Dialogs } from '../components/Widgets';
import { BearingDiagram } from '../components/Charts';

/**
 * S06 地图：机位标记 + 方向射线。
 *
 * 说明：Map Kit（@hms.core.map）需要 AGC 开通地图服务并在工程中配置签名指纹，
 * 本工程未配置 AGC 凭据，因此按 PRD 要求提供「手动坐标 + 简易方位图」的
 * 真实可用降级路径：所有点位与方向均由 WGS84 坐标实时换算，不使用假数据。
 */
@Component
export struct MapPage {
  onNavigate: (route: string) => void = () => {
  };
  onBack: () => void = () => {
  };
  @State ready: boolean = false;
  @State errorText: string = '';
  @State hasPlace: boolean = false;
  @State placeName: string = '';
  @State tzId: string = '';
  @State centerLat: number = 0;
  @State centerLon: number = 0;
  @State radiusText: string = '0.5';
  @State targetAzText: string = '250';
  @State sunAzimuth: number = 0;
  @State extraPoints: string = '';
  @State places: Place[] = [];
  @State addLat: string = '';
  @State addLon: string = '';
  @State addName: string = '';
  @State hint: string = '';

  aboutToAppear(): void {
    this.initPage();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async initPage(): Promise<void> {
    try {
      await AppState.bootstrap(this.hostContext());
      await AppState.reloadData();
      this.places = AppState.places;
      const place = AppState.currentPlace;
      if (place === undefined) {
        this.hasPlace = false;
        this.ready = true;
        return;
      }
      this.hasPlace = true;
      this.placeName = place.name;
      this.tzId = place.tzId;
      this.centerLat = place.latWgs84;
      this.centerLon = place.lonWgs84;
      this.refreshSun();
      this.buildExtraPoints();
      this.ready = true;
    } catch (err) {
      this.errorText = `初始化失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private refreshSun(): void {
    const pos: SunPosition = SolarCalc.position(TimeUtil.now(), this.centerLat, this.centerLon);
    this.sunAzimuth = pos.azimuthDeg;
    this.targetAzText = pos.azimuthDeg.toFixed(0);
  }

  private buildExtraPoints(): void {
    const parts: string[] = [];
    for (const p of this.places) {
      if (Math.abs(p.latWgs84 - this.centerLat) < 0.0000001 && Math.abs(p.lonWgs84 - this.centerLon) < 0.0000001) {
        continue;
      }
      parts.push(`${p.latWgs84},${p.lonWgs84},${p.name}`);
    }
    this.extraPoints = parts.join(';');
  }

  private parse(value: string, fallback: number): number {
    const v = Number.parseFloat(value);
    return Number.isNaN(v) ? fallback : v;
  }

  private async switchCenter(place: Place): Promise<void> {
    AppState.setCurrentPlace(place);
    this.placeName = place.name;
    this.tzId = place.tzId;
    this.centerLat = place.latWgs84;
    this.centerLon = place.lonWgs84;
    this.refreshSun();
    this.buildExtraPoints();
    Dialogs.toast(this.getUIContext(), `中心机位：${place.name}`);
  }

  private async addPlace(): Promise<void> {
    const lat = this.parse(this.addLat, NaN);
    const lon = this.parse(this.addLon, NaN);
    if (Number.isNaN(lat) || lat < -90 || lat > 90 || Number.isNaN(lon) || lon < -180 || lon > 180) {
      this.hint = '请输入合法的纬度（-90~90）与经度（-180~180）。';
      return;
    }
    const name = this.addName.trim().length > 0 ? this.addName.trim() : `手动机位 ${lat.toFixed(3)}, ${lon.toFixed(3)}`;
    try {
      const place = AppState.buildPlace(name, lat, lon, this.tzId, '手动坐标');
      await AppState.savePlace(place);
      await AppState.reloadData();
      this.places = AppState.places;
      this.buildExtraPoints();
      this.addLat = '';
      this.addLon = '';
      this.addName = '';
      this.hint = `已保存「${name}」到机位库。`;
    } catch (err) {
      this.hint = `保存失败：${(err as Error).message}`;
    }
  }

  build() {
    Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({ title: '地图', subtitle: '机位标记与方向射线（本地方位图）' })

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
            title: '还没有中心机位',
            description: '方位图以当前机位为中心。新增机位或直接输入坐标即可立即使用。',
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
              StatusBadge({ label: 'WGS84', tone: 2 })
            }
            .width('100%')
            BearingDiagram({
              centerLat: this.centerLat,
              centerLon: this.centerLon,
              targetAzimuth: this.parse(this.targetAzText, this.sunAzimuth),
              radiusDeg: this.parse(this.radiusText, 0.5),
              labelText: `中心 ${this.centerLat.toFixed(4)}, ${this.centerLon.toFixed(4)} · 半径 ${this.parse(this.radiusText, 0.5)}° · 太阳方位 ${this.sunAzimuth.toFixed(0)}°`,
              extraPoints: this.extraPoints,
              diagramHeight: 300
            })
            Text('金色射线为目标方位（默认取当前太阳方位），青色点为机位库中其它机位，按真实经纬度换算相对位置。')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.lb_muted'))
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          Column({ space: Spacing.M }) {
            Text('方位图参数')
              .fontSize(FontSize.BODY_L)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.lb_ink'))
            NumberField({
              label: '目标方位', unit: '°', valueText: this.targetAzText, placeholder: '0-360',
              onChangeText: (text: string) => {
                this.targetAzText = text;
              }
            })
            NumberField({
              label: '显示半径', unit: '°', valueText: this.radiusText, placeholder: '0.1-5',
              onChangeText: (text: string) => {
                this.radiusText = text;
              }
            })
            Button('用当前太阳方位')
              .type(ButtonType.Normal)
              .width('100%')
              .height(MIN_TOUCH)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_panel2'))
              .fontColor($r('app.color.lb_ink'))
              .onClick(() => {
                this.refreshSun();
              })
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          Column({ space: Spacing.M }) {
            Text('手动新增机位（地图降级路径）')
              .fontSize(FontSize.BODY_L)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.lb_ink'))
            NumberField({
              label: '名称', unit: '', valueText: this.addName, placeholder: '可留空',
              onChangeText: (text: string) => {
                this.addName = text;
              }
            })
            NumberField({
              label: '纬度', unit: '°', valueText: this.addLat, placeholder: '如 31.2372',
              onChangeText: (text: string) => {
                this.addLat = text;
              }
            })
            NumberField({
              label: '经度', unit: '°', valueText: this.addLon, placeholder: '如 121.4900',
              onChangeText: (text: string) => {
                this.addLon = text;
              }
            })
            if (this.hint.length > 0) {
              NoticeBar({ text: this.hint })
            }
            Button('保存到机位库')
              .type(ButtonType.Normal)
              .width('100%')
              .height(MIN_TOUCH)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_primary'))
              .fontColor($r('app.color.lb_bg'))
              .onClick(() => {
                this.addPlace();
              })
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          if (this.places.length > 0) {
            Column({ space: Spacing.S }) {
              Text('机位列表')
                .fontSize(FontSize.BODY_L)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.lb_ink'))
              ForEach(this.places, (place: Place) => {
                Row({ space: Spacing.S }) {
                  Column({ space: Spacing.XS }) {
                    Text(place.name)
                      .fontSize(FontSize.BODY)
                      .fontColor($r('app.color.lb_ink'))
                    Text(`${place.latWgs84.toFixed(4)}, ${place.lonWgs84.toFixed(4)}`)
                      .fontSize(FontSize.CAPTION)
                      .fontColor($r('app.color.lb_muted'))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Button('设为中心')
                    .type(ButtonType.Normal)
                    .height(MIN_TOUCH)
                    .borderRadius(Radius.BUTTON)
                    .backgroundColor($r('app.color.lb_panel2'))
                    .fontColor($r('app.color.lb_ink'))
                    .fontSize(FontSize.CAPTION)
                    .onClick(() => {
                      this.switchCenter(place);
                    })
                }
                .width('100%')
                .padding({ top: Spacing.S, bottom: Spacing.S })
              }, (place: Place) => place.id)
            }
            .width('100%')
            .padding(Spacing.L)
            .backgroundColor($r('app.color.lb_panel'))
            .borderRadius(Radius.CARD)
            .alignItems(HorizontalAlign.Start)
          }

          NoticeBar({
            text: 'Map Kit（@hms.core.map）需要 AGC 开通地图服务并配置签名/Client ID，本工程未接入 AGC 凭据，故不显示在线底图。当前方位图完全离线、由真实坐标计算，功能不受影响。'
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
