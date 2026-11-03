import { JobStatus } from '../model/BaseModels';
import { SessionState } from './SearchSession';

/** 搜索终态类别 */
export class RunKind {
  /** 完成且有窗口 */
  static readonly DONE_OK: number = 0;
  /** 完成且没有窗口（正常结果，需要显示"没有符合条件的时段"） */
  static readonly DONE_EMPTY: number = 1;
  /** 用户取消（未完成，保留部分结果） */
  static readonly CANCELLED: number = 2;
  /** 失败（无法给出可信结论） */
  static readonly FAILED: number = 3;
  /** 机位已切换，结果作废 */
  static readonly STALE: number = 4;
}

/** 终态分派结果：页面只按这里的结果执行，不再自己判断状态 */
export class RunDecision {
  kind: number = RunKind.DONE_OK;
  /** 展示给用户的摘要文案 */
  summary: string = '';
  /** 失败原因（FAILED 时非空） */
  errorText: string = '';
  /** 该写入的 Job 终态 */
  jobStatus: number = JobStatus.DONE;
  /** 是否允许写入"成功搜索"历史 */
  writeSuccessHistory: boolean = false;
  /** 是否展示结果区（候选/窗口列表） */
  showResults: boolean = false;
  /** 结果是否不完整（取消 / 后处理拒绝 / 机位切换） */
  incomplete: boolean = false;
}

/**
 * 搜索终态分派（纯逻辑，便于测试）。
 *
 * 设计目的：页面此前只判断 CANCELLED，导致 SessionState.FAILED（例如太阳位置非有限）
 * 也会继续 finalize、把 Job 写成 DONE、写入成功历史并展示"0 个拍摄窗口"。
 * 这里把「会话状态 + 后处理统计 + 机位是否切换」统一映射成页面可执行的动作。
 */
export class SearchRunPolicy {
  static decide(sessionState: number, windowCount: number, totalBeforeCut: number,
    droppedInvalid: number, unreliableRanges: number, sessionError: string,
    placeChanged: boolean, scopeNote: string): RunDecision {
    const d = new RunDecision();
    const head = `${scopeNote}，自适应区间搜索（1 秒边界）`;
    const cancelled = sessionState === SessionState.CANCELLED;
    const failed = sessionState === SessionState.FAILED || sessionState === SessionState.INVALID;

    if (placeChanged) {
      // 机位已切换：结果作废；Job 终态保留原语义，不能被覆盖成 DONE
      d.kind = RunKind.STALE;
      d.jobStatus = failed ? JobStatus.FAILED : (cancelled ? JobStatus.CANCELLED : JobStatus.DONE);
      d.summary = '机位已切换，本次搜索结果已丢弃，请重新搜索。';
      d.writeSuccessHistory = false;
      d.showResults = false;
      d.incomplete = true;
      d.errorText = failed && sessionError.length > 0 ? sessionError : '';
      return d;
    }

    if (failed) {
      // 太阳位置非有限 / 参数非法：必须显式失败，不能显示成「完成、没有命中」
      d.kind = RunKind.FAILED;
      d.jobStatus = JobStatus.FAILED;
      d.errorText = sessionError.length > 0 ? sessionError : '搜索数据不可用，无法给出可信结果';
      d.summary = windowCount > 0
        ? `${head}结果不完整：${d.errorText}（已保留 ${windowCount} 个已找到窗口）`
        : `${head}失败：${d.errorText}`;
      d.writeSuccessHistory = false;
      d.showResults = windowCount > 0;
      d.incomplete = true;
      return d;
    }

    // 双重防线：即使会话状态被误传为 DONE，只要存在不可靠区间也不能宣称完整成功
    if (unreliableRanges > 0 && sessionState !== SessionState.CANCELLED) {
      d.kind = RunKind.FAILED;
      d.jobStatus = JobStatus.FAILED;
      d.errorText = `有 ${unreliableRanges} 个搜索区间的太阳位置不可用（NaN/Infinity），结果不完整`;
      d.summary = `${head}结果不完整：${d.errorText}` +
        (windowCount > 0 ? `（仅展示 ${windowCount} 个已找到窗口，未完整校验）` : '');
      d.writeSuccessHistory = false;
      d.showResults = windowCount > 0;
      d.incomplete = true;
      return d;
    }

    if (droppedInvalid > 0) {
      // 后处理阶段拒绝了窗口：数据不一致，不得宣称完整成功
      d.kind = RunKind.FAILED;
      d.jobStatus = JobStatus.FAILED;
      d.errorText = `有 ${droppedInvalid} 个窗口在后处理阶段被拒绝（位置与容差不一致），结果不完整`;
      d.summary = `${head}结果不完整：${d.errorText}` +
        (windowCount > 0 ? `（保留 ${windowCount} 个通过校验的窗口）` : '');
      d.writeSuccessHistory = false;
      d.showResults = windowCount > 0;
      d.incomplete = true;
      return d;
    }

    if (cancelled) {
      d.kind = RunKind.CANCELLED;
      d.jobStatus = JobStatus.CANCELLED;
      d.summary = `${head}已取消（未完成）：保留 ${windowCount} 个已找到窗口`;
      d.writeSuccessHistory = false;
      d.showResults = true;
      d.incomplete = true;
      return d;
    }

    if (windowCount > 0) {
      d.kind = RunKind.DONE_OK;
      d.jobStatus = JobStatus.DONE;
      d.summary = `${head}找到 ${windowCount} 个拍摄窗口` +
        (totalBeforeCut > windowCount ? `（共 ${totalBeforeCut} 个，按归一化误差取前 ${windowCount} 个）` : '');
      d.writeSuccessHistory = true;
      d.showResults = true;
      return d;
    }

    d.kind = RunKind.DONE_EMPTY;
    d.jobStatus = JobStatus.DONE;
    d.summary = `${head}完成，没有符合条件的时段（可放宽容差或增加天数）`;
    d.writeSuccessHistory = true;
    d.showResults = true;
    return d;
  }
}
