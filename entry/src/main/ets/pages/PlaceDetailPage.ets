import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH } from '../common/Theme';
import { Place } from '../model/Models';
import { SolarCalc, SolarEvents } from '../services/SolarCalc';
import { TimeUtil } from '../services/TimeUtil';
import { AppDb } from '../repository/AppDb';
import { TopBar, SectionCard, EmptyState, ErrorCard, NoticeBar, MetricTile,
  SkeletonCard, Dialogs } from '../components/Widgets';

/**
 * 机位详情（独立路由）。列表点开进入本页，可设为当前机位或删除。
 */
@Component
export struct PlaceDetailPage {
  placeId: string = '';
  onNavigate: (route: string) => void = () => {
  };
  onBack: () => void = () => {
  };
  @State ready: boolean = false;
  @State errorText: string = '';
  @State place: Place | undefined = undefined;
  @State sunriseText: string = '--:--';
  @State sunsetText: string = '--:--';
  @State goldenText: string = '--';
  @State isCurrent: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async load(): Promise<void> {
    try {
      await AppState.bootstrap(this.hostContext());
      const found: Place | undefined = AppState.findPlace(this.placeId);
      if (found === undefined) {
        this.errorText = '机位不存在或已被删除。';
        this.ready = true;
        return;
      }
      this.place = found;
      this.isCurrent = AppState.currentPlace !== undefined && AppState.currentPlace.id === found.id;
      const dayStart = TimeUtil.startOfLocalDay(found.tzId, TimeUtil.now());
      const ev: SolarEvents = SolarCalc.events(dayStart, found.latWgs84, found.lonWgs84);
      this.sunriseText = ev.sunriseUtc < 0 ? '无' : TimeUtil.formatTime(found.tzId, ev.sunriseUtc);
      this.sunsetText = ev.sunsetUtc < 0 ? '无' : TimeUtil.formatTime(found.tzId, ev.sunsetUtc);
      const w = SolarCalc.lightWindows(dayStart, found.latWgs84, found.lonWgs84, AppState.thresholds());
      this.goldenText = w.goldenEveningStartUtc < 0 ? '无'
        : `${TimeUtil.formatTime(found.tzId, w.goldenEveningStartUtc)}-${TimeUtil.formatTime(found.tzId, w.goldenEveningEndUtc)}`;
      this.ready = true;
    } catch (err) {
      this.errorText = `读取机位失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private setCurrent(): void {
    const place = this.place;
    if (place === undefined) {
      return;
    }
    AppState.setCurrentPlace(place);
    this.isCurrent = true;
    Dialogs.toast(this.getUIContext(), `当前机位：${place.name}`);
  }

  private confirmDelete(): void {
    const place = this.place;
    if (place === undefined) {
      return;
    }
    Dialogs.confirm(this.getUIContext(), '删除机位', `确定删除「${place.name}」？已有的拍摄计划不会被删除。`,
      '删除', () => {
        AppState.deletePlace(place.id).then(() => {
          Dialogs.toast(this.getUIContext(), '已删除');
          this.onBack();
        }).catch((err: Error) => {
          this.errorText = `删除失败：${err.message}`;
        });
      });
  }

  build() {
    Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({ title: '机位详情', subtitle: '坐标、时区与今天的阳光窗口' })

        if (this.errorText.length > 0) {
          ErrorCard({
            message: this.errorText,
            onRetry: () => {
              this.load();
            },
            onBack: () => {
              this.onBack();
            }
          })
        } else if (!this.ready) {
          SkeletonCard()
        } else if (this.place === undefined) {
          EmptyState({
            title: '机位不存在',
            description: '该机位可能已被删除。',
            actionLabel: '返回机位库',
            onAction: () => {
              this.onNavigate('locations');
            }
          })
        } else {
          SectionCard({ cardTitle: this.place.name }) {
            Column({ space: Spacing.S }) {
              if (this.isCurrent) {
                Text('当前工作机位')
                  .fontSize(FontSize.CAPTION)
                  .fontColor($r('app.color.lb_primary'))
                  .width('100%')
              }
              Text(`${this.place.latWgs84.toFixed(4)}°, ${this.place.lonWgs84.toFixed(4)}° · ${this.place.tzId} · ${TimeUtil.offsetLabel(this.place.tzId, TimeUtil.now())}`)
                .fontSize(FontSize.BODY)
                .fontColor($r('app.color.lb_muted'))
                .width('100%')
              if (this.place.tags.length > 0) {
                Text(`标签：${this.place.tags}`)
                  .fontSize(FontSize.CAPTION)
                  .fontColor($r('app.color.lb_accent'))
                  .width('100%')
              }
              if (this.place.note.length > 0) {
                NoticeBar({ text: this.place.note })
              }
              Row({ space: Spacing.S }) {
                MetricTile({ valueText: this.sunriseText, labelText: '今日日出' })
                MetricTile({ valueText: this.sunsetText, labelText: '今日日落' })
              }
              .width('100%')
              Text(`今日黄金时刻（夕）：${this.goldenText}`)
                .fontSize(FontSize.SMALL)
                .fontColor($r('app.color.lb_ink'))
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }

          Row({ space: Spacing.S }) {
            Button(this.isCurrent ? '已是当前机位' : '设为当前机位')
              .type(ButtonType.Normal)
              .height(MIN_TOUCH)
              .layoutWeight(1)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_primary'))
              .fontColor($r('app.color.lb_on_primary'))
              .fontWeight(FontWeight.Bold)
              .enabled(!this.isCurrent)
              .onClick(() => {
                this.setCurrent();
              })
            Button('编辑')
              .type(ButtonType.Normal)
              .height(MIN_TOUCH)
              .layoutWeight(1)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_panel2'))
              .fontColor($r('app.color.lb_ink'))
              .fontWeight(FontWeight.Bold)
              .borderWidth(1)
              .borderColor($r('app.color.lb_line'))
              .onClick(() => {
                this.onNavigate('locations');
              })
          }
          .width('100%')

          Button('删除机位')
            .type(ButtonType.Normal)
            .width('100%')
            .height(MIN_TOUCH)
            .borderRadius(Radius.BUTTON)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.lb_primary'))
            .fontWeight(FontWeight.Bold)
            .borderWidth(1)
            .borderColor($r('app.color.lb_line'))
            .onClick(() => {
              this.confirmDelete();
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
