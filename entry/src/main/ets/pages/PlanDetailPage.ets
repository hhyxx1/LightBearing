import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH } from '../common/Theme';
import { Place, ShootPlan } from '../model/Models';
import { SolarCalc, SunPosition } from '../services/SolarCalc';
import { TimeUtil } from '../services/TimeUtil';
import { AppDb } from '../repository/AppDb';
import { ExportService } from '../services/ExportService';
import { TopBar, SectionCard, EmptyState, ErrorCard, NoticeBar, MetricTile, StatusBadge,
  SkeletonCard, Dialogs } from '../components/Widgets';
import { decodeChecklist } from './PlannerPage';

/**
 * 计划详情（独立路由）。任务书 §11 要求「列表选择与详情跳转」，
 * 列表点开进入本页，而不是在列表里就地展开。
 */
@Component
export struct PlanDetailPage {
  planId: string = '';
  onNavigate: (route: string) => void = () => {
  };
  onBack: () => void = () => {
  };
  @State ready: boolean = false;
  @State errorText: string = '';
  @State plan: ShootPlan | undefined = undefined;
  @State placeName: string = '';
  @State checklistText: string = '';
  @State actualText: string = '';
  @State phaseText: string = '';

  aboutToAppear(): void {
    this.load();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async load(): Promise<void> {
    try {
      await AppState.bootstrap(this.hostContext());
      const found = await AppDb.getPlan(this.planId);
      if (found === undefined) {
        this.errorText = '计划不存在或已被删除。';
        this.ready = true;
        return;
      }
      this.plan = found;
      const place: Place | undefined = AppState.findPlace(found.placeId);
      this.placeName = place === undefined ? found.placeName : place.name;
      const items = decodeChecklist(found.checklist);
      let done = 0;
      for (const item of items) {
        if (item.done) {
          done++;
        }
      }
      this.checklistText = `${items.length} 项，已完成 ${done}`;
      const pos: SunPosition = SolarCalc.position(found.selectedUtc, found.latWgs84, found.lonWgs84);
      const azErr = SolarCalc.angularDistance(pos.azimuthDeg, found.targetAzimuth);
      const altErr = Math.abs(pos.altitudeDeg - found.targetAltitude);
      this.actualText = `实际方位 ${pos.azimuthDeg.toFixed(1)}°（差 ${azErr.toFixed(2)}°）· 高度 ${pos.altitudeDeg.toFixed(1)}°（差 ${altErr.toFixed(2)}°）`;
      this.phaseText = SolarCalc.phaseLabel(SolarCalc.phaseOf(pos.altitudeDeg, AppState.thresholds()));
      this.ready = true;
    } catch (err) {
      this.errorText = `读取计划失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private confirmDelete(): void {
    const plan = this.plan;
    if (plan === undefined) {
      return;
    }
    Dialogs.confirm(this.getUIContext(), '删除计划',
      `确定删除 ${TimeUtil.formatDate(plan.tzId, plan.selectedUtc)} 的计划？`, '删除', () => {
        AppDb.deletePlan(plan.id).then(async () => {
          await AppState.reloadData();
          Dialogs.toast(this.getUIContext(), '已删除');
          this.onBack();
        }).catch((err: Error) => {
          this.errorText = `删除失败：${err.message}`;
        });
      });
  }

  private async exportOne(): Promise<void> {
    const plan = this.plan;
    if (plan === undefined) {
      return;
    }
    const rows: string[][] = [];
    rows.push(['机位', '本地时间', 'UTC时间', '目标方位', '目标高度', '方位容差', '高度容差', '备注']);
    rows.push([this.placeName, TimeUtil.formatDateTime(plan.tzId, plan.selectedUtc),
      new Date(plan.selectedUtc).toISOString(), `${plan.targetAzimuth}`, `${plan.targetAltitude}`,
      `${plan.azTolerance}`, `${plan.altTolerance}`, plan.note]);
    const result = await ExportService.exportCsv(this.hostContext(),
      `lightbearing-plan-${TimeUtil.formatDate(plan.tzId, plan.selectedUtc)}.csv`, rows);
    if (result.ok) {
      await ExportService.recordAsset(result, AppState.currentProjectId);
    }
    Dialogs.toast(this.getUIContext(), result.ok ? `已导出 ${result.bytes} 字节` : result.message);
  }

  build() {
    Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({ title: '计划详情', subtitle: '目标窗口、实际太阳位置与行前清单' })

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
        } else if (this.plan === undefined) {
          EmptyState({
            title: '计划不存在',
            description: '该计划可能已被删除。',
            actionLabel: '返回计划列表',
            onAction: () => {
              this.onNavigate('planner');
            }
          })
        } else {
          SectionCard({ cardTitle: this.placeName }) {
            Column({ space: Spacing.S }) {
              Text(`${TimeUtil.formatDate(this.plan.tzId, this.plan.selectedUtc)} ${TimeUtil.weekdayLabel(TimeUtil.weekday(this.plan.tzId, this.plan.selectedUtc))} ${TimeUtil.formatTime(this.plan.tzId, this.plan.selectedUtc)} · ${TimeUtil.offsetLabel(this.plan.tzId, this.plan.selectedUtc)}`)
                .fontSize(FontSize.BODY)
                .fontColor($r('app.color.lb_muted'))
                .width('100%')
              Row({ space: Spacing.S }) {
                MetricTile({
                  valueText: `${this.plan.targetAzimuth.toFixed(0)}°`,
                  labelText: '目标方位',
                  highlight: true
                })
                MetricTile({
                  valueText: `${this.plan.targetAltitude.toFixed(0)}°`,
                  labelText: '目标高度'
                })
                MetricTile({ valueText: this.phaseText, labelText: '实际光线阶段' })
              }
              .width('100%')
              Text(this.actualText)
                .fontSize(FontSize.SMALL)
                .fontColor($r('app.color.lb_accent'))
                .width('100%')
              Text(`容差：方位 ±${this.plan.azTolerance}° · 高度 ±${this.plan.altTolerance}°`)
                .fontSize(FontSize.CAPTION)
                .fontColor($r('app.color.lb_muted'))
                .width('100%')
              if (this.plan.note.length > 0) {
                Text(`备注：${this.plan.note}`)
                  .fontSize(FontSize.SMALL)
                  .fontColor($r('app.color.lb_muted'))
                  .width('100%')
              }
              if (this.plan.weatherMemo.length > 0) {
                NoticeBar({ text: `天气备忘（手写，非预报）：${this.plan.weatherMemo}` })
              }
              Text(`行前清单：${this.checklistText}`)
                .fontSize(FontSize.SMALL)
                .fontColor($r('app.color.lb_muted'))
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }

          Row({ space: Spacing.S }) {
            Button('编辑')
              .type(ButtonType.Normal)
              .height(MIN_TOUCH)
              .layoutWeight(1)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_primary'))
              .fontColor($r('app.color.lb_on_primary'))
              .fontWeight(FontWeight.Bold)
              .onClick(() => {
                this.onNavigate('planner');
              })
            Button('导出此计划')
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
                this.exportOne();
              })
          }
          .width('100%')

          Button('删除计划')
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
