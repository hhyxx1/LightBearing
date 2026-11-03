import { RunDecision, RunKind } from './SearchRunPolicy';

/**
 * QA-2A / QA-02：搜索页的渲染状态（纯逻辑，页面与测试共用同一份判断）。
 *
 * 关键约束：
 * 1. 只有**页面初始化失败**才整页用 ErrorCard；
 * 2. 一次搜索失败只在表单内显示警示条，表单始终可用；
 * 3. 失败但存在部分窗口时，展示「部分结果」并禁用加入拍摄计划；
 * 4. 正常无命中是正常空态，不是错误；
 * 5. 取消与失败不混用同一文案/动作。
 */
/** 搜索阶段 */
export class SearchPhase {
  /** 尚未搜索过（或已重置） */
  static readonly IDLE: number = 0;
  /** 正在搜索：不展示上一轮任何警示/结果 */
  static readonly RUNNING: number = 1;
  /** 已结束（DONE_OK / DONE_EMPTY / FAILED / CANCELLED / STALE） */
  static readonly FINAL: number = 2;
}

export class ReverseViewState {
  /** 当前搜索阶段（IDLE / RUNNING / FINAL） */
  phase: number = SearchPhase.IDLE;
  /** 进度面板是否可见 */
  showProgressPanel: boolean = false;
  /** 整页错误卡（仅初始化失败） */
  showInitErrorCard: boolean = false;
  /** 骨架屏 */
  showSkeleton: boolean = false;
  /** 「还没有机位」空态 */
  showNoPlace: boolean = false;
  /** 搜索表单是否可见（以上三者都不可见时可见） */
  showForm: boolean = false;
  /** 表单内警示条（搜索失败原因） */
  showSearchWarning: boolean = false;
  /** 部分结果提示条 */
  showPartialBadge: boolean = false;
  /** 结果列表是否展示 */
  showResults: boolean = false;
  /** 是否允许「加入拍摄计划」 */
  allowAddToPlan: boolean = false;
  /** 正常空态提示（无命中且非失败） */
  showEmptyHint: boolean = false;

  static of(initError: boolean, ready: boolean, hasPlace: boolean, searching: boolean,
    hasCompleted: boolean, decision: RunDecision, windowCount: number): ReverseViewState {
    const v = new ReverseViewState();
    v.showInitErrorCard = initError;
    v.showSkeleton = !initError && !ready;
    v.showNoPlace = !initError && ready && !hasPlace;
    v.showForm = !initError && ready && hasPlace;
    v.showProgressPanel = v.showForm && searching;

    if (searching) {
      // 运行中：清掉上一轮的警示/部分结果/空态提示，避免与新一次搜索混在一起
      v.phase = SearchPhase.RUNNING;
      v.showSearchWarning = false;
      v.showPartialBadge = false;
      v.showResults = false;
      v.allowAddToPlan = false;
      v.showEmptyHint = false;
      return v;
    }
    // 从未搜索过才是 IDLE；已经执行过但抛异常（hasCompleted 还没来得及置位）也必须进入失败终态，
    // 否则「搜索失败」的警示会被 IDLE 分支吞掉。
    const looksTerminal = decision.kind === RunKind.FAILED || decision.errorText.length > 0;
    if (!hasCompleted && !looksTerminal) {
      v.phase = SearchPhase.IDLE;
      return v;
    }
    v.phase = SearchPhase.FINAL;

    const failed = decision.kind === RunKind.FAILED;
    const cancelled = decision.kind === RunKind.CANCELLED;
    if (v.showForm) {
      v.showSearchWarning = failed && decision.errorText.length > 0;
      v.showResults = decision.showResults && windowCount > 0;
      v.showPartialBadge = failed && windowCount > 0;
      // 未完整校验的部分结果不允许进入计划
      v.allowAddToPlan = v.showResults && !failed;
      v.showEmptyHint = decision.kind === RunKind.DONE_EMPTY;
      if (cancelled) {
        v.showEmptyHint = false;
      }
    }
    return v;
  }
}
