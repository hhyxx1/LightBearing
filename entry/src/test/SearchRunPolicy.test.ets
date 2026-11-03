import { describe, it, expect } from '@ohos/hypium';
import { SearchRunPolicy, RunDecision, RunKind } from '../main/ets/services/SearchRunPolicy';
import { SessionState } from '../main/ets/services/SearchSession';
import { JobStatus } from '../main/ets/model/BaseModels';

/**
 * 搜索终态分派测试（2C 收尾）：覆盖 DONE / 空结果 / FAILED / CANCELLED / INVALID / 机位切换，
 * 以及 finalize 后处理拒绝窗口（droppedInvalid>0）时不得宣称完整成功。
 *
 * 这些用例走的是 ReversePage 实际调用的同一个纯函数，而不是只比较枚举值。
 */

const SCOPE: string = '请求 14 天、实际搜索 14 天';

function decide(state: number, windows: number, dropped: number, unreliable: number,
  error: string, placeChanged: boolean): RunDecision {
  return SearchRunPolicy.decide(state, windows, windows + dropped, dropped, unreliable, error,
    placeChanged, SCOPE);
}

export default function searchRunPolicyTest() {
  describe('SearchRunPolicy', () => {
    it('done_with_windows_finishes_normally', 0, () => {
      const d = decide(SessionState.DONE, 3, 0, 0, '', false);
      expect(d.kind).assertEqual(RunKind.DONE_OK);
      expect(d.jobStatus).assertEqual(JobStatus.DONE);
      expect(d.writeSuccessHistory).assertTrue();
      expect(d.showResults).assertTrue();
      expect(d.errorText.length).assertEqual(0);
      expect(d.summary.indexOf('3') >= 0).assertTrue();
    });

    it('done_without_windows_is_normal_empty_result', 0, () => {
      const d = decide(SessionState.DONE, 0, 0, 0, '', false);
      expect(d.kind).assertEqual(RunKind.DONE_EMPTY);
      expect(d.jobStatus).assertEqual(JobStatus.DONE);
      expect(d.writeSuccessHistory).assertTrue();
      expect(d.showResults).assertTrue();
      expect(d.summary.indexOf('没有符合条件') >= 0).assertTrue();
    });

    it('failed_without_windows_propagates_reason_and_job_failed', 0, () => {
      const d = decide(SessionState.FAILED, 0, 0, 1, '太阳位置出现非有限值，不能判定为无拍摄机会', false);
      expect(d.kind).assertEqual(RunKind.FAILED);
      expect(d.jobStatus).assertEqual(JobStatus.FAILED);
      expect(d.writeSuccessHistory).assertFalse();
      expect(d.errorText.length > 0).assertTrue();
      expect(d.errorText.indexOf('非有限') >= 0).assertTrue();
      // 不得把失败说成「完成、0 个窗口」
      expect(d.summary.indexOf('没有符合条件') < 0).assertTrue();
      // 失败时不得展示成正常结果区
      expect(d.showResults).assertFalse();
    });

    it('failed_with_partial_windows_is_not_complete', 0, () => {
      const d = decide(SessionState.FAILED, 2, 0, 1, '太阳位置出现非有限值', false);
      expect(d.kind).assertEqual(RunKind.FAILED);
      expect(d.jobStatus).assertEqual(JobStatus.FAILED);
      expect(d.writeSuccessHistory).assertFalse();
      expect(d.incomplete).assertTrue();
    });

    it('cancelled_keeps_incomplete_semantics', 0, () => {
      const d = decide(SessionState.CANCELLED, 5, 0, 0, '', false);
      expect(d.kind).assertEqual(RunKind.CANCELLED);
      expect(d.jobStatus).assertEqual(JobStatus.CANCELLED);
      expect(d.writeSuccessHistory).assertFalse();
      expect(d.incomplete).assertTrue();
      expect(d.summary.indexOf('未完成') >= 0).assertTrue();
    });

    it('dropped_invalid_windows_block_complete_success', 0, () => {
      const d = decide(SessionState.DONE, 3, 2, 0, '', false);
      expect(d.jobStatus === JobStatus.DONE).assertFalse();
      expect(d.writeSuccessHistory).assertFalse();
      expect(d.errorText.length > 0).assertTrue();
      expect(d.incomplete).assertTrue();
    });

    it('place_changed_never_overwrites_failed_with_done', 0, () => {
      const failedStale = decide(SessionState.FAILED, 0, 0, 1, '太阳位置出现非有限值', true);
      expect(failedStale.kind).assertEqual(RunKind.STALE);
      expect(failedStale.jobStatus).assertEqual(JobStatus.FAILED);
      expect(failedStale.writeSuccessHistory).assertFalse();
      expect(failedStale.showResults).assertFalse();

      const cancelledStale = decide(SessionState.CANCELLED, 4, 0, 0, '', true);
      expect(cancelledStale.kind).assertEqual(RunKind.STALE);
      expect(cancelledStale.jobStatus).assertEqual(JobStatus.CANCELLED);
      expect(cancelledStale.writeSuccessHistory).assertFalse();
    });

    it('invalid_session_state_is_failure_not_empty_result', 0, () => {
      const d = decide(SessionState.INVALID, 0, 0, 0, 'maxResults 必须是 1–1000 的整数', false);
      expect(d.kind).assertEqual(RunKind.FAILED);
      expect(d.jobStatus).assertEqual(JobStatus.FAILED);
      expect(d.writeSuccessHistory).assertFalse();
      expect(d.errorText.length > 0).assertTrue();
    });

    it('previous_failure_does_not_pollute_next_run', 0, () => {
      const failed = decide(SessionState.FAILED, 0, 0, 1, '太阳位置出现非有限值', false);
      expect(failed.errorText.length > 0).assertTrue();
      const fresh = decide(SessionState.DONE, 2, 0, 0, '', false);
      expect(fresh.kind).assertEqual(RunKind.DONE_OK);
      expect(fresh.errorText.length).assertEqual(0);
      expect(fresh.writeSuccessHistory).assertTrue();
      expect(fresh.incomplete).assertFalse();
    });
  });
}
