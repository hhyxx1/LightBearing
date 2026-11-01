import { describe, it, expect } from '@ohos/hypium';
import { Timeline, TimelineModel } from '../main/ets/services/Timeline';
import {
  EventText, PlanTimeSelection, SaveCheck, SliderMapping, SliderValue, TimeSelection
} from '../main/ets/services/TimeSelection';
import { LocalResolveStatus } from '../main/ets/services/LocalTimeResolver';
import { EventState } from '../main/ets/services/SolarCalc';

/**
 * 时间选择与保存校验纯逻辑测试。
 * 期望值均为手算固定 UTC 常量；不依赖 i18n（真实时区部分见设备侧 TimeZoneReal）。
 */

const HOUR: number = 3600000.0;
const MINUTE: number = 60000.0;

const SH_START: number = Date.UTC(2026, 9, 29, 16, 0, 0);
const SH_END: number = Date.UTC(2026, 9, 30, 16, 0, 0);
const SPRING_START: number = Date.UTC(2026, 2, 8, 5, 0, 0);
const SPRING_END: number = Date.UTC(2026, 2, 9, 4, 0, 0);
const FALL_START: number = Date.UTC(2026, 10, 1, 4, 0, 0);
const FALL_END: number = Date.UTC(2026, 10, 2, 5, 0, 0);

function resolveResult(status: number, candidates: number[], offsets: number[]): PlanTimeSelection {
  return TimeSelection.fromResolve({
    status: status,
    candidatesUtc: candidates,
    candidateOffsets: offsets,
    reason: ''
  });
}

export default function timeSelectionTest() {
  describe('TimeSelection', () => {
    it('slider_covers_full_23h_day', 0, () => {
      const m: TimelineModel = Timeline.fromBounds(SPRING_START, SPRING_END);
      const start: SliderValue = SliderMapping.toSlider(m, SPRING_START);
      expect(start.valid).assertTrue();
      expect(start.value).assertEqual(0);
      // endUtc 本身不属于半开区间，不能映射成滑块值
      expect(SliderMapping.toSlider(m, SPRING_END).valid).assertFalse();
      const lastInRange = SliderMapping.toSlider(m, SPRING_END - 1);
      expect(lastInRange.valid).assertTrue();
      expect(lastInRange.value).assertEqual(1000);
      // 全区间：每个刻度都落在 [start, end)，且从不等于 end
      for (let v = 0; v <= 1000; v += 50) {
        const p = SliderMapping.toUtc(m, v);
        expect(p.valid).assertTrue();
        expect(p.utcMs >= SPRING_START).assertTrue();
        expect(p.utcMs < SPRING_END).assertTrue();
      }
      const last = SliderMapping.toUtc(m, 1000);
      expect(last.utcMs).assertEqual(SPRING_END - 1);
    });

    it('slider_distinguishes_two_0130_on_25h_day', 0, () => {
      const m = Timeline.fromBounds(FALL_START, FALL_END);
      const first = SliderMapping.toSlider(m, Date.UTC(2026, 10, 1, 5, 30, 0));
      const second = SliderMapping.toSlider(m, Date.UTC(2026, 10, 1, 6, 30, 0));
      expect(first.valid).assertTrue();
      expect(second.valid).assertTrue();
      // 两个 01:30 的 UTC 不同 → 滑块位置必须不同
      expect(second.value > first.value).assertTrue();
      expect(SliderMapping.toUtc(m, first.value).utcMs).assertEqual(Date.UTC(2026, 10, 1, 5, 30, 0));
      expect(SliderMapping.toUtc(m, second.value).utcMs === Date.UTC(2026, 10, 1, 6, 30, 0)).assertTrue();
    });

    it('slider_handles_half_hour_days', 0, () => {
      const shortStart = Date.UTC(2026, 9, 3, 13, 30, 0);
      const shortEnd = shortStart + 23.5 * HOUR;
      const shortModel = Timeline.fromBounds(shortStart, shortEnd);
      const mid = SliderMapping.toUtc(shortModel, 500);
      expect(mid.valid).assertTrue();
      expect(Math.abs(mid.utcMs - (shortStart + 23.5 * HOUR / 2)) <= 60000).assertTrue();

      const longStart = Date.UTC(2026, 3, 4, 13, 0, 0);
      const longEnd = longStart + 24.5 * HOUR;
      const longModel = Timeline.fromBounds(longStart, longEnd);
      const longMid = SliderMapping.toUtc(longModel, 500);
      expect(longMid.valid).assertTrue();
      expect(Math.abs(longMid.utcMs - (longStart + 24.5 * HOUR / 2)) <= 60000).assertTrue();
    });

    it('slider_rejects_invalid_timeline', 0, () => {
      const invalid = Timeline.fromBounds(SH_START, SH_START);
      expect(SliderMapping.toUtc(invalid, 500).valid).assertFalse();
      expect(SliderMapping.toSlider(invalid, SH_START).valid).assertFalse();
      const good = Timeline.fromBounds(SH_START, SH_END);
      expect(SliderMapping.toSlider(good, SH_START - HOUR).valid).assertFalse();
      expect(SliderMapping.toSlider(good, NaN).valid).assertFalse();
      expect(SliderMapping.toUtc(good, NaN).valid).assertFalse();
    });

    it('gap_time_cannot_be_saved', 0, () => {
      const sel = resolveResult(LocalResolveStatus.GAP, [], []);
      expect(sel.isResolved()).assertFalse();
      expect(Number.isNaN(sel.utcMs())).assertTrue();
      expect(sel.message.length > 0).assertTrue();
      const check: SaveCheck = TimeSelection.validateForSave(FALL_START + 6 * HOUR, FALL_START, FALL_END,
        40.7128, -74.006, true, sel);
      expect(check.ok).assertFalse();
      expect(check.errorText.length > 0).assertTrue();
    });

    it('overlap_requires_explicit_choice', 0, () => {
      const firstUtc = Date.UTC(2026, 10, 1, 5, 30, 0);
      const secondUtc = Date.UTC(2026, 10, 1, 6, 30, 0);
      const sel = resolveResult(LocalResolveStatus.OVERLAP, [firstUtc, secondUtc], [-4 * HOUR, -5 * HOUR]);
      // 未选择前不允许保存
      expect(sel.isResolved()).assertFalse();
      const blocked = TimeSelection.validateForSave(firstUtc, FALL_START, FALL_END, 40.7128, -74.006, true, sel);
      expect(blocked.ok).assertFalse();
      // 选第一个候选
      expect(TimeSelection.choose(sel, 0)).assertEqual(firstUtc);
      expect(sel.isResolved()).assertTrue();
      const okFirst = TimeSelection.validateForSave(firstUtc, FALL_START, FALL_END, 40.7128, -74.006, true, sel);
      expect(okFirst.ok).assertTrue();
      // 换成第二个候选
      expect(TimeSelection.choose(sel, 1)).assertEqual(secondUtc);
      const okSecond = TimeSelection.validateForSave(secondUtc, FALL_START, FALL_END, 40.7128, -74.006, true, sel);
      expect(okSecond.ok).assertTrue();
      // 越界索引不改变选择
      expect(Number.isNaN(TimeSelection.choose(sel, 5))).assertTrue();
    });

    it('editing_existing_plan_keeps_original_utc', 0, () => {
      // 编辑但未改时间：selection 传 null → 只校验 UTC 有效性，不重算、不改值
      const original = Date.UTC(2026, 10, 1, 6, 30, 0);
      const check = TimeSelection.validateForSave(original, FALL_START, FALL_END, 40.7128, -74.006, true, null);
      expect(check.ok).assertTrue();
    });

    it('invalid_place_or_zone_or_out_of_range_is_rejected', 0, () => {
      expect(TimeSelection.validateForSave(Date.UTC(2026, 9, 30, 4, 0, 0), SH_START, SH_END,
        91, 0, true, null).ok).assertFalse();
      expect(TimeSelection.validateForSave(Date.UTC(2026, 9, 30, 4, 0, 0), SH_START, SH_END,
        31.2, 181, true, null).ok).assertFalse();
      expect(TimeSelection.validateForSave(Date.UTC(2026, 9, 30, 4, 0, 0), SH_START, SH_END,
        31.2, 121.4, false, null).ok).assertFalse();
      expect(TimeSelection.validateForSave(Date.UTC(2026, 9, 30, 4, 0, 0), SH_START, SH_START,
        31.2, 121.4, true, null).ok).assertFalse();
      expect(TimeSelection.validateForSave(SH_START - MINUTE, SH_START, SH_END,
        31.2, 121.4, true, null).ok).assertFalse();
      expect(TimeSelection.validateForSave(NaN, SH_START, SH_END, 31.2, 121.4, true, null).ok).assertFalse();
      // 1970 年前的负时间戳合法，不能因为 utcMs 为负而拒绝
      const preStart = Date.UTC(1969, 11, 31, 0, 0, 0);
      const preEnd = Date.UTC(1970, 0, 1, 0, 0, 0);
      expect(TimeSelection.validateForSave(Date.UTC(1969, 11, 31, 6, 0, 0), preStart, preEnd,
        31.2, 121.4, true, null).ok).assertTrue();
    });

    it('event_text_differs_by_state', 0, () => {
      expect(EventText.describe(EventState.AVAILABLE, '06:12')).assertEqual('06:12');
      const outside = EventText.describe(EventState.OUTSIDE_DAY, '06:12');
      const noCrossing = EventText.describe(EventState.NO_CROSSING, '06:12');
      const invalid = EventText.describe(EventState.DAY_INVALID, '06:12');
      expect(outside !== noCrossing).assertTrue();
      expect(outside !== invalid).assertTrue();
      expect(noCrossing !== invalid).assertTrue();
      // 绝不能把「事件在所选日之外」写成极夜/极昼
      expect(outside.indexOf('极夜') < 0).assertTrue();
      expect(outside.indexOf('极昼') < 0).assertTrue();
      expect(outside).assertEqual('事件位于所选当地日期之外');
      expect(noCrossing).assertEqual('当日未穿越该高度阈值');
      expect(invalid).assertEqual('日期或时区数据不可用');
    });
  });
}
