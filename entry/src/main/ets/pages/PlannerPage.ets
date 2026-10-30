import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH } from '../common/Theme';
import { Place, ShootPlan, ChecklistItem, IdGen } from '../model/Models';
import { SolarCalc, SunPosition } from '../services/SolarCalc';
import { TimeUtil } from '../services/TimeUtil';
import { AppDb } from '../repository/AppDb';
import { ExportService, ExportResult } from '../services/ExportService';
import { TopBar, EmptyState, ErrorCard, NoticeBar, NumberField, StatusBadge, SkeletonCard, Dialogs } from '../components/Widgets';

/** 清单编码：每行 `1|文本` 或 `0|文本`，避免 JSON 强转带来的类型问题 */
export function encodeChecklist(items: ChecklistItem[]): string {
  const lines: string[] = [];
  for (const item of items) {
    lines.push(`${item.done ? '1' : '0'}|${item.text}`);
  }
  return lines.join('\n');
}

export function decodeChecklist(raw: string): ChecklistItem[] {
  const out: ChecklistItem[] = [];
  if (raw.length === 0) {
    return out;
  }
  const lines: string[] = raw.split('\n');
  let index = 0;
  for (const line of lines) {
    if (line.length === 0) {
      continue;
    }
    const sep = line.indexOf('|');
    if (sep < 0) {
      continue;
    }
    index++;
    const done = line.substring(0, sep) === '1';
    const text = line.substring(sep + 1);
    out.push(ChecklistItem.of(`c${index}`, text, done));
  }
  return out;
}

/**
 * S07 拍摄计划：保存目标机位与候选窗口、行前清单、备注。
 * 计划写入 RDB（事务），重启后可恢复。
 */
@Component
export struct PlannerPage {
  onNavigate: (route: string) => void = () => {
  };
  onBack: () => void = () => {
  };
  @State ready: boolean = false;
  @State errorText: string = '';
  @State plans: ShootPlan[] = [];
  /** 刚删除的计划，用于页面内撤销 */
  @State undoPlan: ShootPlan | undefined = undefined;
  @State undoLabel: string = '';
  @State places: Place[] = [];
  @State editing: boolean = false;
  @State editId: string = '';
  @State placeIndex: number = 0;
  @State placeLabels: string[] = [];
  @State selectedUtc: number = 0;
  @State azText: string = '180';
  @State altText: string = '10';
  @State azTolText: string = '3';
  @State altTolText: string = '3';
  @State noteText: string = '';
  @State weatherText: string = '';
  @State checklist: ChecklistItem[] = [];
  @State newItemText: string = '';
  @State hint: string = '';
  @State exporting: boolean = false;
  @State pickedDate: Date = new Date();

  aboutToAppear(): void {
    this.loadAll();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async loadAll(): Promise<void> {
    try {
      this.errorText = '';
      await AppState.bootstrap(this.hostContext());
      await AppState.reloadData();
      this.plans = AppState.plans;
      this.places = AppState.places;
      const labels: string[] = [];
      for (const p of this.places) {
        labels.push(p.name);
      }
      this.placeLabels = labels;
      this.ready = true;
    } catch (err) {
      this.errorText = `读取计划失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private startNew(): void {
    if (this.places.length === 0) {
      this.onNavigate('locations');
      return;
    }
    this.editing = true;
    AppState.markDirty('拍摄计划编辑');
    this.editId = '';
    this.placeIndex = 0;
    const place = this.places[0];
    this.selectedUtc = TimeUtil.now();
    const local = TimeUtil.toLocal(place.tzId, this.selectedUtc);
    this.pickedDate = new Date(local.year, local.month - 1, local.day);
    const pos = SolarCalc.position(this.selectedUtc, place.latWgs84, place.lonWgs84);
    this.azText = pos.azimuthDeg.toFixed(1);
    this.altText = pos.altitudeDeg.toFixed(1);
    this.azTolText = '3';
    this.altTolText = '3';
    this.noteText = '';
    this.weatherText = '';
    this.checklist = [];
    this.hint = '';
  }

  private startEdit(plan: ShootPlan): void {
    this.editing = true;
    AppState.markDirty('拍摄计划编辑');
    this.editId = plan.id;
    let idx = 0;
    for (let i = 0; i < this.places.length; i++) {
      if (this.places[i].id === plan.placeId) {
        idx = i;
      }
    }
    this.placeIndex = idx;
    this.selectedUtc = plan.selectedUtc;
    const local = TimeUtil.toLocal(plan.tzId, plan.selectedUtc);
    this.pickedDate = new Date(local.year, local.month - 1, local.day);
    this.azText = plan.targetAzimuth.toFixed(1);
    this.altText = plan.targetAltitude.toFixed(1);
    this.azTolText = `${plan.azTolerance}`;
    this.altTolText = `${plan.altTolerance}`;
    this.noteText = plan.note;
    this.weatherText = plan.weatherMemo;
    this.checklist = decodeChecklist(plan.checklist);
    this.hint = '';
  }

  private parse(value: string, fallback: number): number {
    const v = Number.parseFloat(value);
    return Number.isNaN(v) ? fallback : v;
  }

  private currentPlace(): Place | undefined {
    if (this.placeIndex < 0 || this.placeIndex >= this.places.length) {
      return undefined;
    }
    return this.places[this.placeIndex];
  }

  private async savePlan(): Promise<void> {
    const place = this.currentPlace();
    if (place === undefined) {
      this.hint = '请先选择机位。';
      return;
    }
    try {
      let plan: ShootPlan;
      if (this.editId.length > 0) {
        const found = await AppDb.getPlan(this.editId);
        plan = found === undefined ? new ShootPlan() : found;
        if (found === undefined) {
          plan.id = this.editId;
        }
      } else {
        plan = new ShootPlan();
        plan.id = IdGen.next('sp');
      }
      plan.placeId = place.id;
      plan.projectId = AppState.currentProjectId;
      plan.placeName = place.name;
      plan.latWgs84 = place.latWgs84;
      plan.lonWgs84 = place.lonWgs84;
      plan.tzId = place.tzId;
      plan.selectedUtc = this.selectedUtc;
      plan.targetAzimuth = SolarCalc.norm360(this.parse(this.azText, 180));
      plan.targetAltitude = this.parse(this.altText, 10);
      plan.azTolerance = this.parse(this.azTolText, 3);
      plan.altTolerance = this.parse(this.altTolText, 3);
      plan.note = this.noteText;
      plan.weatherMemo = this.weatherText;
      plan.checklist = encodeChecklist(this.checklist);
      await AppDb.savePlan(plan, `保存计划 ${plan.placeName} ${TimeUtil.formatDateTime(plan.tzId, plan.selectedUtc)}`);
      await AppState.reloadData();
      this.plans = AppState.plans;
      this.editing = false;
      AppState.clearDirty();
      this.hint = '已保存。';
      Dialogs.toast(this.getUIContext(), '计划已保存');
    } catch (err) {
      this.hint = `保存失败：${(err as Error).message}`;
    }
  }

  private confirmDelete(plan: ShootPlan): void {
    Dialogs.confirm(this.getUIContext(), '删除计划',
      `确定删除 ${TimeUtil.formatDate(plan.tzId, plan.selectedUtc)} 的计划？`, '删除', () => {
        AppDb.deletePlan(plan.id).then(async () => {
          await AppState.reloadData();
          this.plans = AppState.plans;
          // 危险动作可撤销：页面内撤销条，避免连续弹两个系统对话框
          this.undoPlan = plan;
          this.undoLabel = `已删除 ${TimeUtil.formatDate(plan.tzId, plan.selectedUtc)} 的计划`;
        }).catch((err: Error) => {
          this.hint = `删除失败：${err.message}`;
        });
      });
  }

  private async undoPlanDelete(): Promise<void> {
    const target = this.undoPlan;
    if (target === undefined) {
      return;
    }
    try {
      await AppDb.savePlan(target, `撤销删除并恢复计划 · ${target.placeName}`);
      this.undoPlan = undefined;
      this.undoLabel = '';
      await AppState.reloadData();
      this.plans = AppState.plans;
      Dialogs.toast(this.getUIContext(), '已恢复计划');
    } catch (err) {
      this.hint = `恢复失败：${(err as Error).message}`;
    }
  }

  @Builder
  undoBar() {
    Row({ space: Spacing.M }) {
      Image($r('app.media.ic_history_muted'))
        .width(18)
        .height(18)
        .objectFit(ImageFit.Contain)
      Text(this.undoLabel)
        .fontSize(FontSize.SMALL)
        .fontColor($r('app.color.lb_ink'))
        .layoutWeight(1)
      Button('撤销')
        .type(ButtonType.Normal)
        .height(36)
        .fontSize(FontSize.SMALL)
        .fontWeight(FontWeight.Bold)
        .borderRadius(Radius.BUTTON)
        .backgroundColor($r('app.color.lb_primary'))
        .fontColor($r('app.color.lb_on_primary'))
        .onClick(() => {
          this.undoPlanDelete();
        })
      Button('关闭')
        .type(ButtonType.Normal)
        .height(36)
        .fontSize(FontSize.SMALL)
        .borderRadius(Radius.BUTTON)
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.lb_muted'))
        .onClick(() => {
          this.undoPlan = undefined;
          this.undoLabel = '';
        })
    }
    .width('100%')
    .padding(Spacing.M)
    .backgroundColor($r('app.color.lb_panel2'))
    .borderRadius(Radius.BUTTON)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(VerticalAlign.Center)
  }

  private addChecklistItem(): void {
    const text = this.newItemText.trim();
    if (text.length === 0) {
      return;
    }
    this.checklist.push(ChecklistItem.of(IdGen.next('c'), text, false));
    this.newItemText = '';
  }

  private async exportCsv(): Promise<void> {
    this.exporting = true;
    try {
      const rows: string[][] = [];
      rows.push(['计划ID', '机位', '纬度', '经度', '时区', '本地时间', 'UTC时间', '目标方位', '目标高度',
        '方位容差', '高度容差', '状态', '备注', '天气备忘']);
      for (const plan of this.plans) {
        rows.push([plan.id, plan.placeName, `${plan.latWgs84}`, `${plan.lonWgs84}`, plan.tzId,
          TimeUtil.formatDateTime(plan.tzId, plan.selectedUtc),
          new Date(plan.selectedUtc).toISOString(),
          `${plan.targetAzimuth}`, `${plan.targetAltitude}`, `${plan.azTolerance}`, `${plan.altTolerance}`,
          `${plan.status}`, plan.note, plan.weatherMemo]);
      }
      const result: ExportResult = await ExportService.exportCsv(this.hostContext(), 'lightbearing-plans.csv', rows);
      if (result.ok) {
        await ExportService.recordAsset(result, AppState.currentProjectId);
      }
      if (result.ok) {
        this.hint = `已写出 ${result.bytes} 字节到：${result.uri}`;
      } else {
        this.hint = result.message;
      }
    } catch (err) {
      this.hint = `导出失败：${(err as Error).message}`;
    } finally {
      this.exporting = false;
    }
  }

  @Builder
  editor() {
    Column({ space: Spacing.M }) {
      Text(this.editId.length > 0 ? '编辑计划' : '新建计划')
        .fontSize(FontSize.BODY_L)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.lb_ink'))

      Text('机位')
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_muted'))
      Row({ space: Spacing.S }) {
        ForEach(this.places, (place: Place, index: number) => {
          Button(place.name)
            .type(ButtonType.Normal)
            .height(MIN_TOUCH)
            .borderRadius(Radius.CHIP)
            .backgroundColor(this.placeIndex === index ? $r('app.color.lb_primary') : $r('app.color.lb_panel2'))
            .fontColor(this.placeIndex === index ? $r('app.color.lb_bg') : $r('app.color.lb_ink'))
            .fontSize(FontSize.CAPTION)
            .onClick(() => {
              this.placeIndex = index;
            })
        }, (place: Place) => place.id)
      }
      .width('100%')

      Text('日期')
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_muted'))
      DatePicker({
        start: new Date(2000, 0, 1),
        end: new Date(2100, 11, 31),
        selected: this.pickedDate
      })
        .onDateChange((value: Date) => {
          this.pickedDate = value;
          const place = this.currentPlace();
          if (place !== undefined) {
            const local = TimeUtil.toLocal(place.tzId, this.selectedUtc);
            this.selectedUtc = TimeUtil.fromLocal(place.tzId, value.getFullYear(), value.getMonth() + 1,
              value.getDate(), local.hour, local.minute);
          }
        })

      Text('时间')
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_muted'))
      TimePicker({ selected: this.buildTime() })
        .onChange((value: TimePickerResult) => {
          const place = this.currentPlace();
          if (place === undefined) {
            return;
          }
          const hour = value.hour === undefined ? 12 : value.hour;
          const minute = value.minute === undefined ? 0 : value.minute;
          this.selectedUtc = TimeUtil.fromLocal(place.tzId, this.pickedDate.getFullYear(),
            this.pickedDate.getMonth() + 1, this.pickedDate.getDate(), hour, minute);
        })

      NumberField({
        label: '目标方位', unit: '°', valueText: this.azText, placeholder: '0-360',
        onChangeText: (text: string) => {
          this.azText = text;
        }
      })
      NumberField({
        label: '目标高度', unit: '°', valueText: this.altText, placeholder: '-90-90',
        onChangeText: (text: string) => {
          this.altText = text;
        }
      })
      NumberField({
        label: '方位容差', unit: '°', valueText: this.azTolText, placeholder: '如 3',
        onChangeText: (text: string) => {
          this.azTolText = text;
        }
      })
      NumberField({
        label: '高度容差', unit: '°', valueText: this.altTolText, placeholder: '如 3',
        onChangeText: (text: string) => {
          this.altTolText = text;
        }
      })
      NumberField({
        label: '备注', unit: '', valueText: this.noteText, placeholder: '机位说明',
        onChangeText: (text: string) => {
          this.noteText = text;
        }
      })
      NumberField({
        label: '天气备忘', unit: '', valueText: this.weatherText, placeholder: '手写备注，非天气预报',
        onChangeText: (text: string) => {
          this.weatherText = text;
        }
      })

      Text('行前清单')
        .fontSize(FontSize.BODY)
        .fontColor($r('app.color.lb_muted'))
      ForEach(this.checklist, (item: ChecklistItem) => {
        Row({ space: Spacing.S }) {
          Toggle({ type: ToggleType.Checkbox, isOn: item.done })
            .selectedColor($r('app.color.lb_primary'))
            .onChange((on: boolean) => {
              item.done = on;
            })
          Text(item.text)
            .fontSize(FontSize.BODY)
            .fontColor(item.done ? $r('app.color.lb_muted') : $r('app.color.lb_ink'))
            .decoration({ type: item.done ? TextDecorationType.LineThrough : TextDecorationType.None })
            .layoutWeight(1)
          Button('移除')
            .type(ButtonType.Normal)
            .height(32)
            .fontSize(FontSize.CAPTION)
            .borderRadius(Radius.BUTTON)
            .backgroundColor($r('app.color.lb_panel2'))
            .fontColor($r('app.color.lb_muted'))
            .onClick(() => {
              const next: ChecklistItem[] = [];
              for (const current of this.checklist) {
                if (current.id !== item.id) {
                  next.push(current);
                }
              }
              this.checklist = next;
            })
        }
        .width('100%')
        .constraintSize({ minHeight: MIN_TOUCH })
      }, (item: ChecklistItem) => item.id)

      Row({ space: Spacing.S }) {
        TextInput({ text: this.newItemText, placeholder: '新增清单项' })
          .layoutWeight(1)
          .height(MIN_TOUCH)
          .backgroundColor($r('app.color.lb_panel2'))
          .fontColor($r('app.color.lb_ink'))
          .borderRadius(Radius.BUTTON)
          .onChange((value: string) => {
            this.newItemText = value;
          })
        Button('添加')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_panel2'))
          .fontColor($r('app.color.lb_ink'))
          .onClick(() => {
            this.addChecklistItem();
          })
      }
      .width('100%')

      if (this.hint.length > 0) {
        NoticeBar({ text: this.hint })
      }

      Row({ space: Spacing.S }) {
        Button('保存计划')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_primary'))
          .fontColor($r('app.color.lb_bg'))
          .onClick(() => {
            this.savePlan();
          })
        Button('取消')
          .type(ButtonType.Normal)
          .height(MIN_TOUCH)
          .layoutWeight(1)
          .borderRadius(Radius.BUTTON)
          .backgroundColor($r('app.color.lb_panel2'))
          .fontColor($r('app.color.lb_ink'))
          .onClick(() => {
            this.editing = false;
            AppState.clearDirty();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(Spacing.XL)
    .backgroundColor($r('app.color.lb_panel'))
    .borderRadius(Radius.CARD)
    .borderWidth(1)
    .borderColor($r('app.color.lb_line'))
    .alignItems(HorizontalAlign.Start)
  }

  private buildTime(): Date {
    const place = this.currentPlace();
    if (place === undefined) {
      return new Date();
    }
    const local = TimeUtil.toLocal(place.tzId, this.selectedUtc);
    return new Date(local.year, local.month - 1, local.day, local.hour, local.minute);
  }

  build() {
    Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({ title: '拍摄计划', subtitle: '目标机位、候选窗口与行前清单' })

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
          Column({ space: Spacing.M }) {
            SkeletonCard()
            SkeletonCard()
          }
          .width('100%')
        } else {
          if (!this.editing) {
            Row({ space: Spacing.S }) {
              Button('新建计划')
                .type(ButtonType.Normal)
                .height(MIN_TOUCH)
                .layoutWeight(1)
                .borderRadius(Radius.BUTTON)
                .backgroundColor($r('app.color.lb_primary'))
                .fontColor($r('app.color.lb_bg'))
                .onClick(() => {
                  this.startNew();
                })
              Button(this.exporting ? '导出中…' : '导出 CSV')
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
          }

          if (this.editing) {
            this.editor()
          }

          if (this.undoPlan !== undefined) {
            this.undoBar()
          }

          if (this.plans.length === 0 && !this.editing) {
            EmptyState({
              title: '还没有拍摄计划',
              description: '从太阳轨迹或反向寻光保存一个候选窗口，或在这里手动新建计划。',
              actionLabel: '新建计划',
              onAction: () => {
                this.startNew();
              }
            })
          } else if (!this.editing) {
            Column({ space: Spacing.M }) {
              Row() {
                Text('全部计划')
                  .fontSize(FontSize.BODY_L)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.lb_ink'))
                  .layoutWeight(1)
                StatusBadge({ label: `${this.plans.length} 条`, tone: 1 })
              }
              .width('100%')

              ForEach(this.plans, (plan: ShootPlan) => {
                Column({ space: Spacing.S }) {
                  Row({ space: Spacing.S }) {
                    Text(plan.placeName.length > 0 ? plan.placeName : '未命名机位')
                      .fontSize(FontSize.BODY_L)
                      .fontColor($r('app.color.lb_ink'))
                      .layoutWeight(1)
                      .onClick(() => {
                        this.onNavigate(`planDetail:${plan.id}`);
                      })
                    StatusBadge({ label: plan.status === 0 ? '草稿' : (plan.status === 1 ? '已确认' : '已完成'),
                      tone: plan.status === 1 ? 1 : 3 })
                  }
                  .width('100%')

                  Text(`${TimeUtil.formatDate(plan.tzId, plan.selectedUtc)} ${TimeUtil.weekdayLabel(TimeUtil.weekday(plan.tzId, plan.selectedUtc))} ${TimeUtil.formatTime(plan.tzId, plan.selectedUtc)} · 目标 ${plan.targetAzimuth.toFixed(0)}° / ${plan.targetAltitude.toFixed(0)}°`)
                    .fontSize(FontSize.CAPTION)
                    .fontColor($r('app.color.lb_muted'))
                  Text(describePlanPosition(plan))
                    .fontSize(FontSize.CAPTION)
                    .fontColor($r('app.color.lb_accent'))
                  if (plan.note.length > 0) {
                    Text(plan.note)
                      .fontSize(FontSize.CAPTION)
                      .fontColor($r('app.color.lb_muted'))
                  }
                  if (plan.weatherMemo.length > 0) {
                    Text(`天气备忘：${plan.weatherMemo}`)
                      .fontSize(FontSize.CAPTION)
                      .fontColor($r('app.color.lb_muted'))
                  }
                  Text(`清单 ${decodeChecklist(plan.checklist).length} 项`)
                    .fontSize(FontSize.CAPTION)
                    .fontColor($r('app.color.lb_muted'))

                  Row({ space: Spacing.S }) {
                    Button('编辑')
                      .type(ButtonType.Normal)
                      .height(MIN_TOUCH)
                      .layoutWeight(1)
                      .borderRadius(Radius.BUTTON)
                      .backgroundColor($r('app.color.lb_panel'))
                      .fontColor($r('app.color.lb_ink'))
                      .fontSize(FontSize.CAPTION)
                      .onClick(() => {
                        this.startEdit(plan);
                      })
                    Button('删除')
                      .type(ButtonType.Normal)
                      .height(MIN_TOUCH)
                      .layoutWeight(1)
                      .borderRadius(Radius.BUTTON)
                      .backgroundColor($r('app.color.lb_panel'))
                      .fontColor($r('app.color.lb_primary'))
                      .fontSize(FontSize.CAPTION)
                      .onClick(() => {
                        this.confirmDelete(plan);
                      })
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(Spacing.M)
                .backgroundColor($r('app.color.lb_panel2'))
                .borderRadius(Radius.BUTTON)
                .alignItems(HorizontalAlign.Start)
              }, (plan: ShootPlan) => plan.id)
            }
            .width('100%')
            .padding(Spacing.L)
            .backgroundColor($r('app.color.lb_panel'))
            .borderRadius(Radius.CARD)
            .alignItems(HorizontalAlign.Start)
          }

          if (this.hint.length > 0) {
            NoticeBar({ text: this.hint })
          }

          NoticeBar({
            text: '天气备忘为手工记录，逐光不接入任何天气服务，也不会把备忘内容当作真实预报展示。'
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

/** 计划时刻的实际太阳位置（用于确认计划是否仍匹配） */
function describePlanPosition(plan: ShootPlan): string {
  const pos: SunPosition = SolarCalc.position(plan.selectedUtc, plan.latWgs84, plan.lonWgs84);
  const azErr = SolarCalc.angularDistance(pos.azimuthDeg, plan.targetAzimuth);
  const altErr = Math.abs(pos.altitudeDeg - plan.targetAltitude);
  return `实际方位 ${pos.azimuthDeg.toFixed(1)}°（差 ${azErr.toFixed(1)}°）高度 ${pos.altitudeDeg.toFixed(1)}°（差 ${altErr.toFixed(1)}°）`;
}
