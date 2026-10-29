import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH, Theme } from '../common/Theme';
import { HistoryRecord } from '../model/Models';
import { TimeUtil } from '../services/TimeUtil';
import { LocationService } from '../services/LocationService';
import { SensorService } from '../services/SensorService';
import { AppDb } from '../repository/AppDb';
import { TopBar, ErrorCard, NoticeBar, NumberField, SwitchRow, StatusBadge, Dialogs } from '../components/Widgets';

/**
 * S10 设置：坐标系、时区、定位授权、角度单位、隐私与说明。
 */
@Component
export struct SettingsPage {
  onNavigate: (route: string) => void = () => {
  };
  onBack: () => void = () => {
  };
  @State ready: boolean = false;
  @State errorText: string = '';
  @State themeMode: number = 0;
  @State angleUnit: number = 0;
  @State tzInput: string = '';
  @State goldenUpperText: string = '6';
  @State goldenLowerText: string = '-4';
  @State blueLowerText: string = '-6';
  @State locationGranted: boolean = false;
  @State sensorSupported: boolean = false;
  @State placesCount: number = 0;
  @State plansCount: number = 0;
  @State historyCount: number = 0;
  @State historyItems: HistoryRecord[] = [];
  @State hint: string = '';
  @State showHistory: boolean = false;

  aboutToAppear(): void {
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
      const s = AppState.settings;
      this.themeMode = s.themeMode;
      this.angleUnit = s.angleUnit;
      this.tzInput = s.tzId.length > 0 ? s.tzId : TimeUtil.deviceTimeZoneId();
      this.goldenUpperText = `${s.goldenUpper}`;
      this.goldenLowerText = `${s.goldenLower}`;
      this.blueLowerText = `${s.blueLower}`;
      this.locationGranted = LocationService.hasPermission();
      this.sensorSupported = await SensorService.hasCompass();
      const stats = await AppDb.stats();
      this.placesCount = stats[0];
      this.plansCount = stats[1];
      this.historyCount = stats[2];
      this.ready = true;
    } catch (err) {
      this.errorText = `读取设置失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private parse(value: string, fallback: number): number {
    const v = Number.parseFloat(value);
    return Number.isNaN(v) ? fallback : v;
  }

  private async applyAndSave(): Promise<void> {
    try {
      const ctx = this.hostContext();
      AppState.settings.themeMode = this.themeMode;
      AppState.settings.angleUnit = this.angleUnit;
      AppState.settings.tzId = this.tzInput.trim();
      AppState.settings.goldenUpper = this.parse(this.goldenUpperText, 6);
      AppState.settings.goldenLower = this.parse(this.goldenLowerText, -4);
      AppState.settings.blueLower = this.parse(this.blueLowerText, -6);
      await AppState.persistSettings(ctx);
      this.hint = '设置已保存。';
      Dialogs.toast(this.getUIContext(), '设置已保存');
    } catch (err) {
      this.hint = `保存失败：${(err as Error).message}`;
    }
  }

  private async requestLocation(): Promise<void> {
    const granted = await LocationService.requestPermission(this.hostContext());
    this.locationGranted = granted;
    this.hint = granted ? '已获得前台定位权限。' : '权限被拒绝，手动坐标仍可完成全部计算。';
  }

  private async clearHistory(): Promise<void> {
    Dialogs.confirm(this.getUIContext(), '清空历史记录', '历史记录只用于回溯操作，清空后不可恢复。机位与计划不受影响。',
      '清空', () => {
        AppDb.clearHistory().then(async () => {
          await this.loadAll();
          this.historyItems = [];
          Dialogs.toast(this.getUIContext(), '历史已清空');
        }).catch((err: Error) => {
          this.hint = `清空失败：${err.message}`;
        });
      });
  }

  private async loadHistory(): Promise<void> {
    try {
      this.historyItems = await AppDb.listHistory(20);
      this.showHistory = true;
    } catch (err) {
      this.hint = `读取历史失败：${(err as Error).message}`;
    }
  }

  @Builder
  themeSection() {
    Column({ space: Spacing.M }) {
      Text('外观主题')
        .fontSize(FontSize.BODY_L)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.lb_ink'))
      Row({ space: Spacing.S }) {
        Button('跟随系统')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .borderRadius(Radius.BUTTON)
          .backgroundColor(this.themeMode === 0 ? $r('app.color.lb_primary') : $r('app.color.lb_panel2'))
          .fontColor(this.themeMode === 0 ? $r('app.color.lb_bg') : $r('app.color.lb_ink'))
          .fontSize(FontSize.CAPTION)
          .onClick(() => {
            this.themeMode = 0;
            this.applyAndSave();
          })
        Button('深色')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .borderRadius(Radius.BUTTON)
          .backgroundColor(this.themeMode === 1 ? $r('app.color.lb_primary') : $r('app.color.lb_panel2'))
          .fontColor(this.themeMode === 1 ? $r('app.color.lb_bg') : $r('app.color.lb_ink'))
          .fontSize(FontSize.CAPTION)
          .onClick(() => {
            this.themeMode = 1;
            this.applyAndSave();
          })
        Button('浅色')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .borderRadius(Radius.BUTTON)
          .backgroundColor(this.themeMode === 2 ? $r('app.color.lb_primary') : $r('app.color.lb_panel2'))
          .fontColor(this.themeMode === 2 ? $r('app.color.lb_bg') : $r('app.color.lb_ink'))
          .fontSize(FontSize.CAPTION)
          .onClick(() => {
            this.themeMode = 2;
            this.applyAndSave();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(Spacing.L)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({ title: '设置', subtitle: '坐标系、时区、权限与隐私' })

        if (this.errorText.length > 0) {
          ErrorCard({
            message: this.errorText,
            onRetry: () => {
              this.loadAll();
            },
            onBack: () => {
              this.onBack();
            }
          })
        } else if (!this.ready) {
          Text('读取中…').fontSize(FontSize.BODY).fontColor($r('app.color.lb_muted')).padding(Spacing.XXL)
        } else {
          this.themeSection()

          Column({ space: Spacing.M }) {
            Text('角度与时间')
              .fontSize(FontSize.BODY_L)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.lb_ink'))
            Row({ space: Spacing.S }) {
              Button('度 (°)')
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .layoutWeight(1)
                .borderRadius(Radius.BUTTON)
                .backgroundColor(this.angleUnit === 0 ? $r('app.color.lb_primary') : $r('app.color.lb_panel2'))
                .fontColor(this.angleUnit === 0 ? $r('app.color.lb_bg') : $r('app.color.lb_ink'))
                .onClick(() => {
                  this.angleUnit = 0;
                  this.applyAndSave();
                })
              Button('弧度 (rad)')
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .layoutWeight(1)
                .borderRadius(Radius.BUTTON)
                .backgroundColor(this.angleUnit === 1 ? $r('app.color.lb_primary') : $r('app.color.lb_panel2'))
                .fontColor(this.angleUnit === 1 ? $r('app.color.lb_bg') : $r('app.color.lb_ink'))
                .onClick(() => {
                  this.angleUnit = 1;
                  this.applyAndSave();
                })
            }
            .width('100%')
            NumberField({
              label: '时区 ID', unit: '', valueText: this.tzInput, placeholder: '如 Asia/Shanghai',
              onChangeText: (text: string) => {
                this.tzInput = text;
              }
            })
            Row({ space: Spacing.S }) {
              Button('用本机时区')
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .layoutWeight(1)
                .borderRadius(Radius.BUTTON)
                .backgroundColor($r('app.color.lb_panel2'))
                .fontColor($r('app.color.lb_ink'))
                .fontSize(FontSize.CAPTION)
                .onClick(() => {
                  this.tzInput = TimeUtil.deviceTimeZoneId();
                  this.applyAndSave();
                })
              Button('保存')
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .layoutWeight(1)
                .borderRadius(Radius.BUTTON)
                .backgroundColor($r('app.color.lb_primary'))
                .fontColor($r('app.color.lb_bg'))
                .fontSize(FontSize.CAPTION)
                .onClick(() => {
                  this.applyAndSave();
                })
            }
            .width('100%')
            Text(`当前时区偏移：${TimeUtil.offsetLabel(this.tzInput, TimeUtil.now())}`)
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.lb_muted'))
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          Column({ space: Spacing.M }) {
            Text('黄金/蓝调定义')
              .fontSize(FontSize.BODY_L)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.lb_ink'))
            NumberField({
              label: '黄金上限', unit: '°', valueText: this.goldenUpperText, placeholder: '如 6',
              onChangeText: (text: string) => {
                this.goldenUpperText = text;
              }
            })
            NumberField({
              label: '黄金下限', unit: '°', valueText: this.goldenLowerText, placeholder: '如 -4',
              onChangeText: (text: string) => {
                this.goldenLowerText = text;
              }
            })
            NumberField({
              label: '蓝调下限', unit: '°', valueText: this.blueLowerText, placeholder: '如 -6',
              onChangeText: (text: string) => {
                this.blueLowerText = text;
              }
            })
            Button('保存定义')
              .type(ButtonType.Normal)
              .width('100%')
              .height(MIN_TOUCH)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_primary'))
              .fontColor($r('app.color.lb_bg'))
              .onClick(() => {
                this.applyAndSave();
              })
            NoticeBar({
              text: '默认定义：黄金时刻为太阳高度 +6° 到 -4°；蓝调为 -4° 到 -6°（民用曙暮光）。日出日落按几何高度 -0.833°（上边缘 + 标准折射）。'
            })
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          Column({ space: Spacing.M }) {
            Text('权限与设备能力')
              .fontSize(FontSize.BODY_L)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.lb_ink'))
            Row({ space: Spacing.S }) {
              Text('前台定位权限')
                .fontSize(FontSize.BODY)
                .fontColor($r('app.color.lb_ink'))
                .layoutWeight(1)
              StatusBadge({ label: this.locationGranted ? '已授权' : '未授权', tone: this.locationGranted ? 1 : 3 })
            }
            .width('100%')
            .constraintSize({ minHeight: MIN_TOUCH })
            Row({ space: Spacing.S }) {
              Text('方向传感器')
                .fontSize(FontSize.BODY)
                .fontColor($r('app.color.lb_ink'))
                .layoutWeight(1)
              StatusBadge({ label: this.sensorSupported ? '可用' : '不可用', tone: this.sensorSupported ? 2 : 3 })
            }
            .width('100%')
            .constraintSize({ minHeight: MIN_TOUCH })
            Button('申请/检查定位权限')
              .type(ButtonType.Normal)
              .width('100%')
              .height(MIN_TOUCH)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_panel2'))
              .fontColor($r('app.color.lb_ink'))
              .onClick(() => {
                this.requestLocation();
              })
            NoticeBar({
              text: '逐光只申请 ohos.permission.APPROXIMATELY_LOCATION 与 LOCATION（user_grant，前台一次定位），不申请后台定位、相机、媒体库写入等受限或无关权限，也不使用受限 ACL。'
            })
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          Column({ space: Spacing.M }) {
            Text('本地数据')
              .fontSize(FontSize.BODY_L)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.lb_ink'))
            Row({ space: Spacing.S }) {
              Text(`机位 ${this.placesCount} 个 · 计划 ${this.plansCount} 条 · 历史 ${this.historyCount} 条`)
                .fontSize(FontSize.BODY)
                .fontColor($r('app.color.lb_ink'))
                .layoutWeight(1)
            }
            .width('100%')
            Row({ space: Spacing.S }) {
              Button(this.showHistory ? '刷新历史' : '查看历史')
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .layoutWeight(1)
                .borderRadius(Radius.BUTTON)
                .backgroundColor($r('app.color.lb_panel2'))
                .fontColor($r('app.color.lb_ink'))
                .fontSize(FontSize.CAPTION)
                .onClick(() => {
                  this.loadHistory();
                })
              Button('清空历史')
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .layoutWeight(1)
                .borderRadius(Radius.BUTTON)
                .backgroundColor($r('app.color.lb_panel2'))
                .fontColor($r('app.color.lb_primary'))
                .fontSize(FontSize.CAPTION)
                .onClick(() => {
                  this.clearHistory();
                })
            }
            .width('100%')

            if (this.showHistory) {
              if (this.historyItems.length === 0) {
                Text('暂无历史记录。')
                  .fontSize(FontSize.CAPTION)
                  .fontColor($r('app.color.lb_muted'))
              } else {
                ForEach(this.historyItems, (item: HistoryRecord) => {
                  Row({ space: Spacing.S }) {
                    Text(item.kind)
                      .fontSize(FontSize.CAPTION)
                      .fontColor($r('app.color.lb_accent'))
                      .width(64)
                    Text(item.summary)
                      .fontSize(FontSize.CAPTION)
                      .fontColor($r('app.color.lb_ink'))
                      .layoutWeight(1)
                    Text(TimeUtil.formatTime(TimeUtil.deviceTimeZoneId(), item.createdAt))
                      .fontSize(FontSize.CAPTION)
                      .fontColor($r('app.color.lb_muted'))
                  }
                  .width('100%')
                  .padding({ top: 4, bottom: 4 })
                }, (item: HistoryRecord) => item.id)
              }
            }
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          if (this.hint.length > 0) {
            NoticeBar({ text: this.hint })
          }

          Column({ space: Spacing.S }) {
            Text('关于逐光')
              .fontSize(FontSize.BODY_L)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.lb_ink'))
            Text('逐光 / LightBearing · 好光线，值得提前抵达')
              .fontSize(FontSize.BODY)
              .fontColor($r('app.color.lb_ink'))
            Text('版本 1.0.0（versionCode 1）· 包名 com.hhyxx.lightbearing · HarmonyOS API 26')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.lb_muted'))
            Text('坐标系：内部统一 WGS84。地图服务若使用 GCJ-02，需要官方转换后再显示。')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.lb_muted'))
            Text('算法：NOAA/Meeus 低精度级数，1900-2100 年方位角残差 < 0.5°；日出日落定义见上。')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.lb_muted'))
            Text('隐私：全部数据保存在本机 RDB，不联网、无埋点、无第三方 SDK；仅在你主动点击时使用定位/传感器。')
              .fontSize(FontSize.CAPTION)
              .fontColor($r('app.color.lb_muted'))
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          Button('回到今日光线')
            .type(ButtonType.Normal)
            .width('100%')
            .height(MIN_TOUCH)
            .borderRadius(Radius.BUTTON)
            .backgroundColor($r('app.color.lb_panel2'))
            .fontColor($r('app.color.lb_ink'))
            .onClick(() => {
              this.onNavigate('home');
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
