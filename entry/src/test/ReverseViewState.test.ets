import { describe, it, expect } from '@ohos/hypium';
import { ReverseViewState, SearchPhase } from '../main/ets/services/ReverseViewState';
import { RunDecision, RunKind } from '../main/ets/services/SearchRunPolicy';

/**
 * QA-2A/2B 回归：搜索页渲染状态（页面与测试共用同一份纯逻辑）。
 * 阶段：IDLE（未搜索/已重置）、RUNNING（进行中，不显示上一轮任何警示或结果）、FINAL（终态）。
 */

function decision(kind: number, error: string, showResults: boolean, incomplete: boolean): RunDecision {
  const d = new RunDecision();
  d.kind = kind;
  d.errorText = error;
  d.showResults = showResults;
  d.incomplete = incomplete;
  return d;
}

/** 已完成的正常页面（ready + 有机位，非运行中，已有一次终态） */
function finalState(kind: number, error: string, showResults: boolean, incomplete: boolean,
  windows: number): ReverseViewState {
  return ReverseViewState.of(false, true, true, false, true,
    decision(kind, error, showResults, incomplete), windows);
}

export default function reverseViewStateTest() {
  describe('ReverseViewState', () => {
    it('done_ok_shows_form_and_results', 0, () => {
      const v = finalState(RunKind.DONE_OK, '', true, false, 3);
      expect(v.phase).assertEqual(SearchPhase.FINAL);
      expect(v.showInitErrorCard).assertFalse();
      expect(v.showForm).assertTrue();
      expect(v.showResults).assertTrue();
      expect(v.showSearchWarning).assertFalse();
      expect(v.showPartialBadge).assertFalse();
      expect(v.allowAddToPlan).assertTrue();
      expect(v.showEmptyHint).assertFalse();
      expect(v.showProgressPanel).assertFalse();
    });

    it('done_empty_shows_normal_empty_hint', 0, () => {
      const v = finalState(RunKind.DONE_EMPTY, '', true, false, 0);
      expect(v.showForm).assertTrue();
      expect(v.showResults).assertFalse();
      expect(v.showEmptyHint).assertTrue();
      expect(v.showSearchWarning).assertFalse();
      expect(v.allowAddToPlan).assertFalse();
    });

    it('failed_without_windows_keeps_form_with_warning', 0, () => {
      const v = finalState(RunKind.FAILED, '太阳位置出现非有限值', false, true, 0);
      expect(v.showForm).assertTrue();
      expect(v.showInitErrorCard).assertFalse();
      expect(v.showSearchWarning).assertTrue();
      expect(v.showResults).assertFalse();
      expect(v.showPartialBadge).assertFalse();
      expect(v.allowAddToPlan).assertFalse();
      expect(v.showEmptyHint).assertFalse();
    });

    it('failed_with_partial_windows_disables_add_to_plan', 0, () => {
      const v = finalState(RunKind.FAILED, '结果不完整', true, true, 2);
      expect(v.showForm).assertTrue();
      expect(v.showSearchWarning).assertTrue();
      expect(v.showResults).assertTrue();
      expect(v.showPartialBadge).assertTrue();
      expect(v.allowAddToPlan).assertFalse();
    });

    it('cancelled_shows_incomplete_results_still_addable', 0, () => {
      const v = finalState(RunKind.CANCELLED, '', true, true, 4);
      expect(v.showForm).assertTrue();
      expect(v.showSearchWarning).assertFalse();
      expect(v.showResults).assertTrue();
      expect(v.showPartialBadge).assertFalse();
      expect(v.allowAddToPlan).assertTrue();
    });

    it('stale_clears_results_but_keeps_form', 0, () => {
      const v = finalState(RunKind.STALE, '', false, true, 0);
      expect(v.showForm).assertTrue();
      expect(v.showResults).assertFalse();
      expect(v.allowAddToPlan).assertFalse();
    });

    it('idle_before_first_search_has_no_warning_or_results', 0, () => {
      const v = ReverseViewState.of(false, true, true, false, false, new RunDecision(), 0);
      expect(v.phase).assertEqual(SearchPhase.IDLE);
      expect(v.showForm).assertTrue();
      expect(v.showSearchWarning).assertFalse();
      expect(v.showResults).assertFalse();
      expect(v.showEmptyHint).assertFalse();
      expect(v.allowAddToPlan).assertFalse();
      expect(v.showProgressPanel).assertFalse();
    });

    it('running_hides_previous_warning_and_results', 0, () => {
      // 上一轮 FAILED 有部分结果，但新一次搜索进行中：不得展示旧警示/旧结果
      const prev = decision(RunKind.FAILED, '上一轮失败', true, true);
      const v = ReverseViewState.of(false, true, true, true, true, prev, 3);
      expect(v.phase).assertEqual(SearchPhase.RUNNING);
      expect(v.showForm).assertTrue();
      expect(v.showProgressPanel).assertTrue();
      expect(v.showSearchWarning).assertFalse();
      expect(v.showPartialBadge).assertFalse();
      expect(v.showResults).assertFalse();
      expect(v.allowAddToPlan).assertFalse();
      expect(v.showEmptyHint).assertFalse();
    });

    it('init_error_uses_full_page_card_not_form', 0, () => {
      const v = ReverseViewState.of(true, true, true, false, false, new RunDecision(), 0);
      expect(v.showInitErrorCard).assertTrue();
      expect(v.showForm).assertFalse();
      expect(v.showSkeleton).assertFalse();
      expect(v.showResults).assertFalse();
    });

    it('not_ready_shows_skeleton_and_no_place_shows_empty_state', 0, () => {
      const loading = ReverseViewState.of(false, false, false, false, false, new RunDecision(), 0);
      expect(loading.showSkeleton).assertTrue();
      expect(loading.showForm).assertFalse();
      const noPlace = ReverseViewState.of(false, true, false, false, false, new RunDecision(), 0);
      expect(noPlace.showNoPlace).assertTrue();
      expect(noPlace.showForm).assertFalse();
    });

    it('exception_run_shows_warning_even_before_completion_flag', 0, () => {
      // 搜索过程中抛异常：页面可能来不及把 hasCompleted 置位，但必须进入失败终态并显示原因
      const failed = decision(RunKind.FAILED, '搜索失败：创建任务失败', false, true);
      const v = ReverseViewState.of(false, true, true, false, false, failed, 0);
      expect(v.phase).assertEqual(SearchPhase.FINAL);
      expect(v.showForm).assertTrue();
      expect(v.showSearchWarning).assertTrue();
      expect(v.showEmptyHint).assertFalse();
      expect(v.showResults).assertFalse();
      expect(v.allowAddToPlan).assertFalse();
    });

    it('exception_with_partial_windows_marks_partial_and_blocks_plan', 0, () => {
      const failed = decision(RunKind.FAILED, '搜索失败：写入任务状态失败', true, true);
      const v = ReverseViewState.of(false, true, true, false, false, failed, 2);
      expect(v.phase).assertEqual(SearchPhase.FINAL);
      expect(v.showSearchWarning).assertTrue();
      expect(v.showResults).assertTrue();
      expect(v.showPartialBadge).assertTrue();
      expect(v.allowAddToPlan).assertFalse();
    });

    it('new_search_clears_previous_exception_warning', 0, () => {
      const failed = decision(RunKind.FAILED, '搜索失败：创建任务失败', false, true);
      const running = ReverseViewState.of(false, true, true, true, false, failed, 0);
      expect(running.phase).assertEqual(SearchPhase.RUNNING);
      expect(running.showSearchWarning).assertFalse();
    });
  });
}
