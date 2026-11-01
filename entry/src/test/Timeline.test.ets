import { describe, it, expect } from '@ohos/hypium';
import { Timeline, TimelineModel } from '../main/ets/services/Timeline';

/**
 * 真实时间轴纯逻辑测试（无 Kit 依赖）。
 * 覆盖 23/24/25/23.5/24.5 小时本地日、1970 年前负时间戳与各类无效输入；
 * 期望值全部是手算的固定 UTC 常量，不调用被测函数生成。
 */

const HOUR: number = 3600000.0;
const MINUTE: number = 60000.0;

/** 上海 2026-10-30 本地日 */
const SH_START: number = Date.UTC(2026, 9, 29, 16, 0, 0);
const SH_END: number = Date.UTC(2026, 9, 30, 16, 0, 0);
/** 纽约春季 2026-03-08（23h） */
const NY_SPRING_START: number = Date.UTC(2026, 2, 8, 5, 0, 0);
const NY_SPRING_END: number = Date.UTC(2026, 2, 9, 4, 0, 0);
/** 纽约秋季 2026-11-01（25h） */
const NY_FALL_START: number = Date.UTC(2026, 10, 1, 4, 0, 0);
const NY_FALL_END: number = Date.UTC(2026, 10, 2, 5, 0, 0);

export default function timelineTest() {
  describe('Timeline', () => {
    it('regular_24h_day_covers_whole_day', 0, () => {
      const m: TimelineModel = Timeline.fromBounds(SH_START, SH_END);
      expect(m.valid).assertTrue();
      expect(m.durationMs).assertEqual(24 * HOUR);
      const samples = Timeline.sampleTimes(m, 30 * MINUTE);
      // 48 个整半小时采样 + 一个末端补点（保证曲线画到接近 end）
      expect(samples.length).assertEqual(49);
      expect(samples[0]).assertEqual(SH_START);
      expect(samples[samples.length - 1]).assertEqual(SH_END - 1);
      // 严格落在 [start, end)
      for (let i = 0; i < samples.length; i++) {
        expect(samples[i] >= SH_START).assertTrue();
        expect(samples[i] < SH_END).assertTrue();
        if (i > 0) {
          expect(samples[i] > samples[i - 1]).assertTrue();
        }
      }
      // 正午 12:00 本地 = 04:00Z，比例应为 0.5
      expect(m.ratioOf(Date.UTC(2026, 9, 30, 4, 0, 0))).assertEqual(0.5);
      expect(m.ratioOf(SH_START)).assertEqual(0);
      expect(m.ratioOf(SH_END)).assertEqual(-1);
    });

    it('spring_forward_23h_never_samples_next_day', 0, () => {
      const m = Timeline.fromBounds(NY_SPRING_START, NY_SPRING_END);
      expect(m.valid).assertTrue();
      expect(m.durationMs).assertEqual(23 * HOUR);
      const samples = Timeline.sampleTimes(m, 30 * MINUTE);
      expect(samples.length).assertEqual(47);
      for (const t of samples) {
        expect(t < NY_SPRING_END).assertTrue();
      }
      expect(samples[samples.length - 1]).assertEqual(NY_SPRING_END - 1);
      // 次日 00:00 之后不属于本日
      expect(m.ratioOf(NY_SPRING_END + HOUR)).assertEqual(-1);
      // 本地 02:00-02:59 不存在，它的两个候选 UTC（07:00Z/07:30Z）在这里都落在缺口内：
      // 时间轴按 UTC 连续，因此这两个 UTC 时刻仍然是合法采样点（曲线不断裂）
      expect(m.ratioOf(Date.UTC(2026, 2, 8, 7, 0, 0)) > 0).assertTrue();
      expect(m.ratioOf(Date.UTC(2026, 2, 8, 7, 30, 0)) > 0).assertTrue();
    });

    it('fall_back_25h_covers_extra_hour', 0, () => {
      const m = Timeline.fromBounds(NY_FALL_START, NY_FALL_END);
      expect(m.valid).assertTrue();
      expect(m.durationMs).assertEqual(25 * HOUR);
      const samples = Timeline.sampleTimes(m, 30 * MINUTE);
      expect(samples.length).assertEqual(51);
      expect(samples[samples.length - 1]).assertEqual(NY_FALL_END - 1);
      // 两个本地 01:30 对应 05:30Z 与 06:30Z，必须落在不同 x 比例上
      const first = m.ratioOf(Date.UTC(2026, 10, 1, 5, 30, 0));
      const second = m.ratioOf(Date.UTC(2026, 10, 1, 6, 30, 0));
      expect(first > 0).assertTrue();
      expect(second > first).assertTrue();
      expect(Math.abs((second - first) - 1 / 25) < 0.0001).assertTrue();
    });

    it('half_hour_days_have_correct_duration', 0, () => {
      const shortStart = Date.UTC(2026, 9, 3, 13, 30, 0);
      const shortEnd = shortStart + 23.5 * HOUR;
      const shortModel = Timeline.fromBounds(shortStart, shortEnd);
      expect(shortModel.durationMs).assertEqual(23.5 * HOUR);
      expect(Math.abs(shortModel.ratioOf(shortStart + 23.5 * HOUR / 2) - 0.5) < 0.0001).assertTrue();

      const longStart = Date.UTC(2026, 3, 4, 13, 0, 0);
      const longEnd = longStart + 24.5 * HOUR;
      const longModel = Timeline.fromBounds(longStart, longEnd);
      expect(longModel.durationMs).assertEqual(24.5 * HOUR);
      expect(Math.abs(longModel.ratioOf(longStart + 24.5 * HOUR / 2) - 0.5) < 0.0001).assertTrue();
    });

    it('pre_epoch_negative_timestamps_are_valid', 0, () => {
      // 1969-12-31 上海本地日：[1969-12-30T16:00Z, 1969-12-31T16:00Z)
      const start = Date.UTC(1969, 11, 30, 16, 0, 0);
      const end = Date.UTC(1969, 11, 31, 16, 0, 0);
      expect(start < 0).assertTrue();
      expect(end < 0).assertTrue();
      const m = Timeline.fromBounds(start, end);
      expect(m.valid).assertTrue();
      expect(m.ratioOf(start)).assertEqual(0);
      const samples = Timeline.sampleTimes(m, HOUR);
      expect(samples.length > 0).assertTrue();
      expect(samples[0]).assertEqual(start);
      expect(samples[0] < 0).assertTrue();
      for (const t of samples) {
        expect(t >= start && t < end).assertTrue();
      }
    });

    it('invalid_inputs_do_not_produce_models_or_coordinates', 0, () => {
      expect(Timeline.fromBounds(NaN, SH_END).valid).assertFalse();
      expect(Timeline.fromBounds(SH_START, NaN).valid).assertFalse();
      expect(Timeline.fromBounds(Infinity, SH_END).valid).assertFalse();
      expect(Timeline.fromBounds(SH_START, SH_START).valid).assertFalse();
      expect(Timeline.fromBounds(SH_START, SH_START - HOUR).valid).assertFalse();

      const invalid = Timeline.fromBounds(SH_START, SH_START);
      expect(Timeline.sampleTimes(invalid, HOUR).length).assertEqual(0);
      expect(invalid.ratioOf(SH_START)).assertEqual(-1);
      expect(Timeline.utcAtRatio(invalid, 0.5)).assertEqual(-1);

      const good = Timeline.fromBounds(SH_START, SH_END);
      expect(good.ratioOf(NaN)).assertEqual(-1);
      expect(good.ratioOf(Infinity)).assertEqual(-1);
      expect(good.ratioOf(SH_START - 1)).assertEqual(-1);
      expect(Timeline.sampleTimes(good, 0).length).assertEqual(0);
      expect(Timeline.sampleTimes(good, NaN).length).assertEqual(0);
      expect(Timeline.utcAtRatio(good, -0.1)).assertEqual(-1);
      expect(Timeline.utcAtRatio(good, 1.1)).assertEqual(-1);
    });

    it('tick_ratios_and_progress_labels', 0, () => {
      const wide: number[] = Timeline.tickRatios(360);
      expect(wide.length).assertEqual(8);
      expect(wide[0]).assertEqual(0);
      expect(wide[4]).assertEqual(0.5);
      const narrow: number[] = Timeline.tickRatios(240);
      expect(narrow.length).assertEqual(4);
      expect(Timeline.tickRatios(NaN).length).assertEqual(4);

      expect(Timeline.progressLabel(0)).assertEqual('0%');
      expect(Timeline.progressLabel(0.25)).assertEqual('25%');
      expect(Timeline.progressLabel(1)).assertEqual('100%');

      const m = Timeline.fromBounds(SH_START, SH_END);
      expect(Timeline.utcAtRatio(m, 0)).assertEqual(SH_START);
      expect(Timeline.utcAtRatio(m, 0.5)).assertEqual(SH_START + 12 * HOUR);
      // 比例 1 取半开区间末端（end - 1）
      expect(Timeline.utcAtRatio(m, 1)).assertEqual(SH_END - 1);
    });

    it('selected_time_outside_range_is_not_drawable', 0, () => {
      const m = Timeline.fromBounds(NY_FALL_START, NY_FALL_END);
      expect(m.ratioOf(NY_FALL_START - MINUTE)).assertEqual(-1);
      expect(m.ratioOf(NY_FALL_END)).assertEqual(-1);
      const inside = m.ratioOf(NY_FALL_END - MINUTE);
      expect(inside >= 0 && inside < 1).assertTrue();
    });
  });
}
