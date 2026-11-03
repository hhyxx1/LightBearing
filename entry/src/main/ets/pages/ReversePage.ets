import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { FontSize, Radius, Spacing, MIN_TOUCH } from '../common/Theme';
import { Place, ShootPlan, Candidate, SearchGoal, IdGen } from '../model/Models';
import { Job, JobStatus } from '../model/BaseModels';
import { SolarCalc } from '../services/SolarCalc';
import { ReverseSearch, DayRange, SearchPlan } from '../services/ReverseSearch';
import { LocalDayBounds } from '../services/LocalTimeResolver';
import { SearchSession, SessionState } from '../services/SearchSession';
import { ShootWindow } from '../model/ShootWindow';
import { SearchOutcome, WindowSortMode } from '../services/ReverseSearch';
import { RunDecision, RunKind, SearchRunPolicy } from '../services/SearchRunPolicy';
import { ReverseViewState } from '../services/ReverseViewState';
import { TimelineLabels } from '../services/TimelineLabels';
import { TimeUtil } from '../services/TimeUtil';
import { AppDb } from '../repository/AppDb';
import { TopBar, EmptyState, ErrorCard, NoticeBar, NumberField, StatusBadge, SkeletonCard,
  ProgressSheet, Dialogs } from '../components/Widgets';

/**
 * S03 反向寻光：给定方位/高度容差与日期范围，批量搜索满足条件的时刻。
 * 所有候选均由 SolarCalc 现场算出，误差可复算。
 */
@Component
export struct ReversePage {
  onNavigate: (route: string) => void = () => {
  };
  onBack: () => void = () => {
  };
  @State ready: boolean = false;
  @State errorText: string = '';
  /** 页面初始化失败（整页不可用） */
  @State initErrorText: string = '';
  /** 本次结果不完整（FAILED 的部分结果），不允许直接加入拍摄计划 */
  @State partialResults: boolean = false;
  /** 最近一次搜索的终态决定（渲染状态由 ReverseViewState 统一推导） */
  private lastDecision: RunDecision = new RunDecision();
  @State hasPlace: boolean = false;
  @State placeName: string = '';
  @State tzId: string = '';
  @State azInput: string = '250';
  @State altInput: string = '10';
  @State azTolInput: string = '3';
  @State altTolInput: string = '3';
  @State daysInput: string = '14';
  @State daylightOnly: boolean = false;
  @State searching: boolean = false;
  @State candidates: Candidate[] = [];
  @State windows: ShootWindow[] = [];
  @State windowNotes: string[] = [];
  @State searched: boolean = false;
  @State summary: string = '';
  @State lastMs: number = 0;
  /** 后台任务进度浮层 */
  @State sheetVisible: boolean = false;
  @State sheetPercent: number = 0;
  @State sheetDetail: string = '';
  private cancelRequested: boolean = false;

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
      this.ready = true;
    } catch (err) {
      this.initErrorText = `读取机位失败：${(err as Error).message}`;
      this.ready = true;
    }
  }

  private parse(value: string, fallback: number): number {
    const v = Number.parseFloat(value);
    return Number.isNaN(v) ? fallback : v;
  }

  /** 让出一帧，保证进度浮层能刷新（长任务不会卡住 UI 线程） */
  /** 页面渲染状态：与测试共用同一份纯逻辑 */
  private viewState(): ReverseViewState {
    return ReverseViewState.of(this.initErrorText.length > 0, this.ready, this.hasPlace,
      this.searching, this.searched, this.lastDecision, this.candidates.length);
  }

  private async nextFrame(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, 0);
    });
  }

  private cancelSearch(): void {
    this.cancelRequested = true;
  }

  private async runSearch(): Promise<void> {
    const place = AppState.currentPlace;
    if (place === undefined) {
      return;
    }
    this.searching = true;
    this.cancelRequested = false;
    this.candidates = [];
    this.windows = [];
    this.windowNotes = [];
    this.errorText = '';
    this.partialResults = false;
    // 完全重置上一轮终态：未结束前不展示旧警示/旧结果/旧空态
    this.searched = false;
    this.lastDecision = new RunDecision();
    this.summary = '';
    this.sheetVisible = true;
    this.sheetPercent = 0;
    this.sheetDetail = '准备搜索…';
    const job = Job.of(IdGen.next('job'), 'reverse');
    job.status = JobStatus.RUNNING;
    const jobId = job.id;
    try {
      await AppDb.createJob(job);
      const goal = new SearchGoal();
      goal.placeId = place.id;
      goal.latWgs84 = place.latWgs84;
      goal.lonWgs84 = place.lonWgs84;
      goal.tzId = place.tzId;
      goal.azimuthTarget = SolarCalc.norm360(this.parse(this.azInput, 180));
      goal.altitudeTarget = this.parse(this.altInput, 10);
      goal.azTolerance = Math.max(0.1, this.parse(this.azTolInput, 3));
      goal.altTolerance = Math.max(0.1, this.parse(this.altTolInput, 3));
      const days = Math.max(1, Math.min(365, Math.round(this.parse(this.daysInput, 14))));
      goal.rangeDays = days;
      goal.daylightOnly = this.daylightOnly;
      goal.maxResults = 30;

      // 逐日取真实本地日边界；真正被整日跳过的日期可跳过并计数，数据不可用必须中止
      const boundsList: LocalDayBounds[] = [];
      const startLocal = TimeUtil.toLocal(place.tzId, TimeUtil.now());
      if (!startLocal.valid) {
        throw new Error('机位时区不可用，无法确定本地日期');
      }
      let cursorDate: number[] = [startLocal.year, startLocal.month, startLocal.day];
      for (let i = 0; i < days; i++) {
        boundsList.push(TimeUtil.localDayBounds(place.tzId, cursorDate[0], cursorDate[1], cursorDate[2]));
        const next = new Date(Date.UTC(cursorDate[0], cursorDate[1] - 1, cursorDate[2] + 1));
        cursorDate = [next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate()];
      }
      const plan: SearchPlan = SearchPlan.plan(boundsList);
      if (plan.errorText.length > 0) {
        throw new Error(plan.errorText);
      }
      const ranges: DayRange[] = plan.ranges;

      const t0 = new Date().getTime();
      const th = AppState.thresholds();
      const placeIdAtStart = place.id;
      const session = new SearchSession(goal, th, ranges);
      if (session.getState() === SessionState.INVALID) {
        throw new Error(session.getError());
      }
      // 分片推进：每片最多约 12ms，片与片之间让出一帧；取消在下一次分片前生效
      this.sheetPercent = 0;
      while (!session.isFinished()) {
        if (this.cancelRequested) {
          session.cancel();
          break;
        }
        session.step(12);
        this.sheetPercent = session.getProgressPercent();
        const curDate = TimeUtil.formatDate(place.tzId, session.getCurrentRangeStartUtc());
        this.sheetDetail = `${curDate} · 已找到 ${session.getWindows().length} 个窗口`;
        await AppDb.updateJob(jobId, JobStatus.RUNNING, this.sheetPercent, '');
        await this.nextFrame();
      }
      const sessionState = session.getState();
      const placeNow = AppState.currentPlace;
      const placeChanged = placeNow === undefined || placeNow.id !== placeIdAtStart;
      const skippedNote = plan.skippedDays > 0 ? `，跳过 ${plan.skippedDays} 天不存在的日期` : '';
      const scopeNote = `请求 ${plan.requestedDays} 天、实际搜索 ${ranges.length} 天${skippedNote}`;

      // 只有完成或取消才做后处理；FAILED/INVALID 的数据不可信，直接用会话已收集的部分结果
      let windows: ShootWindow[] = [];
      let droppedInvalid = 0;
      let unresolved = 0;
      if (sessionState === SessionState.DONE || sessionState === SessionState.CANCELLED) {
        const outcome: SearchOutcome = ReverseSearch.finalizeWindows(goal, th, session.getWindows(),
          WindowSortMode.BEST, goal.maxResults, undefined, session.getStats(), ranges);
        if (outcome.errorText.length > 0) {
          throw new Error(outcome.errorText);
        }
        windows = outcome.windows;
        droppedInvalid = outcome.droppedInvalid;
        unresolved = outcome.stats.unresolvedIntervals;
      } else {
        windows = session.getWindows();
      }

      const decision: RunDecision = SearchRunPolicy.decide(sessionState, windows.length,
        windows.length + droppedInvalid, droppedInvalid, session.getUnreliableRanges(),
        session.getError(), placeChanged, scopeNote);
      this.lastDecision = decision;
      const elapsed = new Date().getTime() - t0;
      this.lastMs = elapsed;

      if (decision.kind === RunKind.STALE) {
        this.candidates = [];
        this.windows = [];
        this.windowNotes = [];
        this.searched = false;
        this.errorText = '';
        this.partialResults = false;
        this.summary = decision.summary;
        await AppDb.updateJob(jobId, decision.jobStatus, this.sheetPercent, decision.errorText);
        return;
      }

      if (decision.showResults && windows.length > 0) {
        const mapped: Candidate[] = [];
        const notes: string[] = [];
        for (const w of windows) {
          mapped.push(Candidate.of(w.bestUtc, w.bestAzimuth, w.bestAltitude, w.bestAzError,
            w.bestAltError, w.phase));
          const startText = `${TimeUtil.formatTime(place.tzId, w.startUtc)}` +
            `（${TimelineLabels.offsetText(TimeUtil.offsetMs(place.tzId, w.startUtc))}）`;
          const endText = `${TimeUtil.formatTime(place.tzId, w.endUtc - 1)}`;
          const durMin = Math.max(1, Math.round(w.durationMs() / 60000));
          notes.push(`窗口 ${startText} – ${endText} · 约 ${durMin} 分钟` +
            `${w.degenerate ? ' · 单点命中' : ''}${w.endUtc - w.startUtc < 60000 ? '（不足 1 分钟）' : ''}`);
        }
        this.candidates = mapped;
        this.windows = windows;
        this.windowNotes = notes;
      } else if (!decision.showResults) {
        this.candidates = [];
        this.windows = [];
        this.windowNotes = [];
      }
      this.searched = decision.showResults;
      // 搜索失败只出「警示条」，不再用错误卡顶掉整个表单
      this.errorText = decision.kind === RunKind.FAILED ? decision.errorText : '';
      this.partialResults = decision.incomplete && decision.kind === RunKind.FAILED;
      this.summary = `${decision.summary}（用时 ${elapsed} ms）`;
      if (unresolved > 0) {
        this.summary += ` 有 ${unresolved} 个区间未能在最大深度内判定。`;
      }
      await AppDb.updateJob(jobId, decision.jobStatus,
        decision.jobStatus === JobStatus.DONE ? 100 : this.sheetPercent, decision.errorText);
      if (decision.writeSuccessHistory) {
        await AppDb.addHistory('reverse',
          `反向寻光 ${place.name} 目标 ${goal.azimuthTarget.toFixed(0)}°/${goal.altitudeTarget.toFixed(0)}° 命中 ${windows.length} 个窗口`,
          `${days}天`);
      }
    } catch (err) {
      this.errorText = `搜索失败：${(err as Error).message}`;
      this.partialResults = false;
      this.lastDecision = new RunDecision();
      this.lastDecision.kind = RunKind.FAILED;
      this.lastDecision.errorText = this.errorText;
      // 已执行过（即使异常）：进入失败终态，保证原因可见；表单保持可用
      this.searched = true;
      try {
        await AppDb.updateJob(jobId, JobStatus.FAILED, this.sheetPercent, `${(err as Error).message}`);
      } catch (inner) {
        // 任务状态写入失败不覆盖主错误
      }
    } finally {
      this.searching = false;
      this.sheetVisible = false;
    }
  }

  private async addToPlan(candidate: Candidate): Promise<void> {
    const place = AppState.currentPlace;
    if (place === undefined) {
      return;
    }
    try {
      const plan = new ShootPlan();
      plan.id = IdGen.next('r');
      plan.placeId = place.id;
      plan.placeName = place.name;
      plan.latWgs84 = place.latWgs84;
      plan.lonWgs84 = place.lonWgs84;
      plan.tzId = place.tzId;
      plan.selectedUtc = candidate.utcMs;
      plan.targetAzimuth = candidate.azimuth;
      plan.targetAltitude = candidate.altitude;
      plan.azTolerance = this.parse(this.azTolInput, 3);
      plan.altTolerance = this.parse(this.altTolInput, 3);
      plan.note = `反向寻光命中 · 误差 ${candidate.azError.toFixed(2)}° / ${candidate.altError.toFixed(2)}°`;
      plan.checklist = '[]';
      plan.projectId = AppState.currentProjectId;
      await AppDb.savePlan(plan, `反向寻光加入计划 · ${place.name}`);
      await AppState.reloadData();
      Dialogs.toast(this.getUIContext(), '已加入拍摄计划');
    } catch (err) {
      Dialogs.toast(this.getUIContext(), `保存失败：${(err as Error).message}`);
    }
  }

  build() {
    Stack() {
      Scroll() {
      Column({ space: Spacing.M }) {
        TopBar({ title: '反向寻光', subtitle: '指定方位与高度，找出可达的时间窗口' })

        if (this.viewState().showInitErrorCard) {
          ErrorCard({
            message: this.initErrorText,
            onRetry: () => {
              this.initErrorText = '';
              this.initPage();
            },
            onBack: () => {
              this.onBack();
            }
          })
        } else if (this.viewState().showSkeleton) {
          Column({ space: Spacing.M }) {
            SkeletonCard()
            SkeletonCard()
          }
          .width('100%')
        } else if (this.viewState().showNoPlace) {
          EmptyState({
            title: '还没有机位',
            description: '反向寻光需要机位坐标。请先新增机位或使用当前位置。',
            actionLabel: '去机位库',
            onAction: () => {
              this.onNavigate('locations');
            }
          })
        } else {
          Column({ space: Spacing.M }) {
            if (this.viewState().showSearchWarning) {
              NoticeBar({ text: this.errorText })
            }
            if (this.viewState().showPartialBadge) {
              NoticeBar({ text: '以下为部分结果（搜索未完整完成），已禁用「加入拍摄计划」。请修正条件后重新搜索。' })
            }
            Text(this.placeName).fontSize(FontSize.BODY).fontColor($r('app.color.lb_muted'))
            NumberField({
              label: '目标方位角', unit: '°', valueText: this.azInput, placeholder: '0-360',
              onChangeText: (text: string) => {
                this.azInput = text;
              }
            })
            NumberField({
              label: '目标高度角', unit: '°', valueText: this.altInput, placeholder: '-90-90',
              onChangeText: (text: string) => {
                this.altInput = text;
              }
            })
            NumberField({
              label: '方位容差', unit: '°', valueText: this.azTolInput, placeholder: '例如 3',
              onChangeText: (text: string) => {
                this.azTolInput = text;
              }
            })
            NumberField({
              label: '高度容差', unit: '°', valueText: this.altTolInput, placeholder: '例如 3',
              onChangeText: (text: string) => {
                this.altTolInput = text;
              }
            })
            NumberField({
              label: '搜索天数', unit: '天', valueText: this.daysInput, placeholder: '1-365',
              onChangeText: (text: string) => {
                this.daysInput = text;
              }
            })
            Row({ space: Spacing.M }) {
              Text('仅保留白昼（太阳在地平线以上）')
                .fontSize(FontSize.BODY)
                .fontColor($r('app.color.lb_ink'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.daylightOnly })
                .selectedColor($r('app.color.lb_primary'))
                .onChange((on: boolean) => {
                  this.daylightOnly = on;
                })
            }
            .width('100%')
            .constraintSize({ minHeight: MIN_TOUCH })

            Button(this.searching ? '正在搜索…' : '搜索候选时段')
              .id('reverse_search_btn')
              .type(ButtonType.Normal)
              .width('100%')
              .height(MIN_TOUCH)
              .borderRadius(Radius.BUTTON)
              .backgroundColor($r('app.color.lb_primary'))
              .fontColor($r('app.color.lb_bg'))
              .enabled(!this.searching)
              .onClick(() => {
                this.runSearch();
              })
          }
          .width('100%')
          .padding(Spacing.L)
          .backgroundColor($r('app.color.lb_panel'))
          .borderRadius(Radius.CARD)
          .alignItems(HorizontalAlign.Start)

          if (this.searching) {
            Row({ space: Spacing.S }) {
              LoadingProgress().width(26).height(26).color($r('app.color.lb_primary'))
              Text('逐日计算中，请稍候…').fontSize(FontSize.BODY).fontColor($r('app.color.lb_muted'))
            }
            .padding(Spacing.L)
          }

          if (this.searched && !this.searching) {
            Column({ space: Spacing.S }) {
              Row({ space: Spacing.S }) {
                Text('候选时段')
                  .fontSize(FontSize.BODY_L)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.lb_ink'))
                  .layoutWeight(1)
                StatusBadge({ label: `${this.candidates.length} 个`, tone: this.candidates.length > 0 ? 1 : 3 })
              }
              .width('100%')
              NoticeBar({ text: this.summary })
                .id('reverse_summary')

              if (this.candidates.length === 0) {
                Text('在该容差与日期范围内没有满足条件的时刻。可以放宽容差、增加天数，或调整目标角。')
                  .fontSize(FontSize.BODY)
                  .fontColor($r('app.color.lb_muted'))
              } else {
                ForEach(this.candidates, (c: Candidate, index: number) => {
                  Column({ space: Spacing.S }) {
                    Row({ space: Spacing.S }) {
                      Text(`${TimeUtil.formatDate(this.tzId, c.utcMs)} ${TimeUtil.formatTime(this.tzId, c.utcMs)} · ${TimeUtil.weekdayLabel(TimeUtil.weekday(this.tzId, c.utcMs))}`)
                        .fontSize(FontSize.BODY_L)
                        .fontColor($r('app.color.lb_ink'))
                        .layoutWeight(1)
                      StatusBadge({ label: SolarCalc.phaseLabel(c.phase), tone: c.phase === 5 ? 1 : 2 })
                    }
                    .width('100%')
                    Text(`方位 ${c.azimuth.toFixed(2)}°（误差 ${c.azError.toFixed(2)}°）· 高度 ${c.altitude.toFixed(2)}°（误差 ${c.altError.toFixed(2)}°）`)
                      .fontSize(FontSize.CAPTION)
                      .fontColor($r('app.color.lb_muted'))
                    if (index < this.windowNotes.length) {
                      Text(this.windowNotes[index])
                        .fontSize(FontSize.CAPTION)
                        .fontColor($r('app.color.lb_accent'))
                    }
                    Button(this.viewState().allowAddToPlan ? '加入拍摄计划' : '部分结果，暂不可加入计划')
                      .type(ButtonType.Normal)
                      .height(MIN_TOUCH)
                      .width('100%')
                      .borderRadius(Radius.BUTTON)
                      .backgroundColor($r('app.color.lb_panel2'))
                      .fontColor(this.viewState().allowAddToPlan ? $r('app.color.lb_ink') : $r('app.color.lb_muted'))
                      .enabled(this.viewState().allowAddToPlan)
                      .onClick(() => {
                        if (!this.viewState().allowAddToPlan) {
                          return;
                        }
                        this.addToPlan(c);
                      })
                  }
                  .width('100%')
                  .padding(Spacing.M)
                  .backgroundColor($r('app.color.lb_panel2'))
                  .borderRadius(Radius.BUTTON)
                  .alignItems(HorizontalAlign.Start)
                }, (c: Candidate) => `${c.utcMs}`)
              }
            }
            .width('100%')
            .padding(Spacing.L)
            .backgroundColor($r('app.color.lb_panel'))
            .borderRadius(Radius.CARD)
            .alignItems(HorizontalAlign.Start)
          }
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

      ProgressSheet({
        visible: this.sheetVisible,
        sheetTitle: '反向寻光搜索中',
        detail: this.sheetDetail,
        percent: this.sheetPercent,
        cancellable: true,
        onCancel: () => {
          this.cancelSearch();
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
