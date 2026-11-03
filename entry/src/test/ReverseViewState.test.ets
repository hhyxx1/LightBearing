import { describe, it, expect } from '@ohos/hypium';
import { ReverseViewState } from '../main/ets/services/ReverseViewState';
import { RunDecision, RunKind } from '../main/ets/services/SearchRunPolicy';

/**
 * QA-2A / QA-02 回归：搜索页渲染状态（页面与测试共用同一份纯逻辑）。
 * 关键约束：只有初始化失败才整页错误卡；搜索失败保留表单；部分结果禁用加入计划。
 */

function decision(kind: number, error: string, showResults: boolean, incomplete: boolean): RunDecision {
  const d = new RunDecision();
  d.kind = kind;
  d.errorText = error;
  d.showResults = showResults;
  d.incomplete = incomplete;
  return d;
}

export default function reverseViewStateTest() {
  describe('ReverseViewState', () => {
    it('done_ok_shows_form_and_results', 0, () => {
      const v = ReverseViewState.of(false, true, true, decision(RunKind.DONE_OK, '', true, false), 3);
      expect(v.showInitErrorCard).assertFalse();
      expect(v.showForm).assertTrue();
      expect(v.showResults).assertTrue();
      expect(v.showSearchWarning).assertFalse();
      expect(v.showPartialBadge).assertFalse();
      expect(v.allowAddToPlan).assertTrue();
      expect(v.showEmptyHint).assertFalse();
    });

    it('done_empty_shows_normal_empty_hint', 0, () => {
      const v = ReverseViewState.of(false, true, true, decision(RunKind.DONE_EMPTY, '', true, false), 0);
      expect(v.showForm).assertTrue();
      expect(v.showResults).assertFalse();
      expect(v.showEmptyHint).assertTrue();
      expect(v.showSearchWarning).assertFalse();
      expect(v.allowAddToPlan).assertFalse();
    });

    it('failed_without_windows_keeps_form_with_warning', 0, () => {
      const v = ReverseViewState.of(false, true, true,
        decision(RunKind.FAILED, '太阳位置出现非有限值', false, true), 0);
      expect(v.showForm).assertTrue();
      expect(v.showInitErrorCard).assertFalse();
      expect(v.showSearchWarning).assertTrue();
      expect(v.showResults).assertFalse();
      expect(v.showPartialBadge).assertFalse();
      expect(v.allowAddToPlan).assertFalse();
    });

    it('failed_with_partial_windows_shows_warning_and_results_but_no_plan', 0, () => {
      const v = ReverseViewState.of(false, true, true,
        decision(RunKind.FAILED, '结果不完整', true, true), 2);
      expect(v.showForm).assertTrue();
      expect(v.showSearchWarning).assertTrue();
      expect(v.showResults).assertTrue();
      expect(v.showPartialBadge).assertTrue();
      // 未完整校验的部分结果不允许进入拍摄计划
      expect(v.allowAddToPlan).assertFalse();
    });

    it('cancelled_shows_incomplete_results_still_addable', 0, () => {
      const v = ReverseViewState.of(false, true, true,
        decision(RunKind.CANCELLED, '', true, true), 4);
      expect(v.showForm).assertTrue();
      expect(v.showSearchWarning).assertFalse();
      expect(v.showResults).assertTrue();
      expect(v.showPartialBadge).assertFalse();
      expect(v.allowAddToPlan).assertTrue();
    });

    it('stale_clears_results_but_keeps_form', 0, () => {
      const v = ReverseViewState.of(false, true, true,
        decision(RunKind.STALE, '', false, true), 0);
      expect(v.showForm).assertTrue();
      expect(v.showResults).assertFalse();
      expect(v.allowAddToPlan).assertFalse();
    });

    it('init_error_uses_full_page_card_not_form', 0, () => {
      const v = ReverseViewState.of(true, true, true, new RunDecision(), 0);
      expect(v.showInitErrorCard).assertTrue();
      expect(v.showForm).assertFalse();
      expect(v.showSkeleton).assertFalse();
      expect(v.showResults).assertFalse();
    });

    it('not_ready_shows_skeleton_and_no_place_shows_empty_state', 0, () => {
      const loading = ReverseViewState.of(false, false, false, new RunDecision(), 0);
      expect(loading.showSkeleton).assertTrue();
      expect(loading.showForm).assertFalse();
      const noPlace = ReverseViewState.of(false, true, false, new RunDecision(), 0);
      expect(noPlace.showNoPlace).assertTrue();
      expect(noPlace.showForm).assertFalse();
    });
  });
}
