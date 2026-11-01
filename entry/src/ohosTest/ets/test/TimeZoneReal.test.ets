import { describe, it, expect } from '@ohos/hypium';
import { i18n } from '@kit.LocalizationKit';
import { TimeUtil } from '../../../main/ets/services/TimeUtil';
import { DayKind, LocalDayBounds, LocalResolveResult, LocalResolveStatus } from '../../../main/ets/services/LocalTimeResolver';
import { Timeline, TimelineModel } from '../../../main/ets/services/Timeline';
import { TimelineLabels, TimelineTick } from '../../../main/ets/services/TimelineLabels';

/**
 * 真实 IANA 时区的设备侧测试。
 *
 * 为什么放在 ohosTest：宿主机单测里的 @kit.LocalizationKit 是空实现，
 * 拿不到真实时区数据。这里的期望值全部是手算的固定 UTC 常量，
 * 由 IANA “first Sunday of October / first Sunday of April” 等公开规则推出，
 * 不是调用被测函数生成的。
 */

const HOUR: number = 3600000.0;
const HALF_HOUR: number = 1800000.0;

export default function timeZoneRealTest() {
  describe('TimeZoneReal', () => {
    it('new_york_spring_forward_2026_03_08', 0, () => {
      const b: LocalDayBounds = TimeUtil.localDayBounds('America/New_York', 2026, 3, 8);
      expect(b.valid).assertTrue();
      expect(b.startUtc).assertEqual(Date.UTC(2026, 2, 8, 5, 0, 0));
      expect(b.endUtc).assertEqual(Date.UTC(2026, 2, 9, 4, 0, 0));
      expect(b.durationMs).assertEqual(23 * HOUR);
      expect(b.kind).assertEqual(DayKind.SHORT);

      const gap: LocalResolveResult = TimeUtil.resolveLocal('America/New_York', 2026, 3, 8, 2, 30);
      expect(gap.status).assertEqual(LocalResolveStatus.GAP);
      expect(gap.candidatesUtc.length).assertEqual(0);
    });

    it('new_york_fall_back_2026_11_01', 0, () => {
      const b = TimeUtil.localDayBounds('America/New_York', 2026, 11, 1);
      expect(b.valid).assertTrue();
      expect(b.startUtc).assertEqual(Date.UTC(2026, 10, 1, 4, 0, 0));
      expect(b.endUtc).assertEqual(Date.UTC(2026, 10, 2, 5, 0, 0));
      expect(b.durationMs).assertEqual(25 * HOUR);
      expect(b.kind).assertEqual(DayKind.LONG);

      const overlap = TimeUtil.resolveLocal('America/New_York', 2026, 11, 1, 1, 30);
      expect(overlap.status).assertEqual(LocalResolveStatus.OVERLAP);
      expect(overlap.candidatesUtc.length).assertEqual(2);
      expect(overlap.candidatesUtc[0]).assertEqual(Date.UTC(2026, 10, 1, 5, 30, 0));
      expect(overlap.candidatesUtc[1]).assertEqual(Date.UTC(2026, 10, 1, 6, 30, 0));
    });

    it('shanghai_regular_day_2026_10_30', 0, () => {
      const b = TimeUtil.localDayBounds('Asia/Shanghai', 2026, 10, 30);
      expect(b.valid).assertTrue();
      expect(b.startUtc).assertEqual(Date.UTC(2026, 9, 29, 16, 0, 0));
      expect(b.endUtc).assertEqual(Date.UTC(2026, 9, 30, 16, 0, 0));
      expect(b.durationMs).assertEqual(24 * HOUR);
      expect(b.kind).assertEqual(DayKind.NORMAL);
      // 当地正午必须唯一且换算一致
      const noon = TimeUtil.resolveLocal('Asia/Shanghai', 2026, 10, 30, 12, 0);
      expect(noon.status).assertEqual(LocalResolveStatus.UNIQUE);
      expect(noon.candidatesUtc[0]).assertEqual(Date.UTC(2026, 9, 30, 4, 0, 0));
      const local = TimeUtil.toLocal('Asia/Shanghai', noon.candidatesUtc[0]);
      expect(local.hour).assertEqual(12);
      expect(local.minute).assertEqual(0);
    });

    it('kathmandu_non_hour_offset', 0, () => {
      // UTC+05:45 = 20700000 ms
      expect(TimeUtil.offsetMs('Asia/Kathmandu', Date.UTC(2026, 9, 30, 0, 0, 0))).assertEqual(20700000);
      const b = TimeUtil.localDayBounds('Asia/Kathmandu', 2026, 10, 30);
      expect(b.valid).assertTrue();
      expect(b.startUtc).assertEqual(Date.UTC(2026, 9, 29, 18, 15, 0));
      expect(b.endUtc).assertEqual(Date.UTC(2026, 9, 30, 18, 15, 0));
      expect(b.durationMs).assertEqual(24 * HOUR);
    });

    it('lord_howe_half_hour_dst', 0, () => {
      // 南半球：4 月第一个周日回拨（24.5 小时），10 月第一个周日跳表（23.5 小时）
      const long = TimeUtil.localDayBounds('Australia/Lord_Howe', 2026, 4, 5);
      expect(long.valid).assertTrue();
      expect(long.durationMs).assertEqual(24 * HOUR + HALF_HOUR);
      expect(long.kind).assertEqual(DayKind.LONG);

      const short = TimeUtil.localDayBounds('Australia/Lord_Howe', 2026, 10, 4);
      expect(short.valid).assertTrue();
      expect(short.durationMs).assertEqual(23 * HOUR + HALF_HOUR);
      expect(short.kind).assertEqual(DayKind.SHORT);

      // 跳表缺口内 02:15 不存在
      const gap = TimeUtil.resolveLocal('Australia/Lord_Howe', 2026, 10, 4, 2, 15);
      expect(gap.status).assertEqual(LocalResolveStatus.GAP);
      // 回拨重复时段 01:45 出现两次
      const overlap = TimeUtil.resolveLocal('Australia/Lord_Howe', 2026, 4, 5, 1, 45);
      expect(overlap.status).assertEqual(LocalResolveStatus.OVERLAP);
      expect(overlap.candidatesUtc.length).assertEqual(2);
      expect(overlap.candidatesUtc[1] - overlap.candidatesUtc[0]).assertEqual(HALF_HOUR);
    });

    it('kiritimati_utc_plus_14', 0, () => {
      expect(TimeUtil.offsetMs('Pacific/Kiritimati', Date.UTC(2026, 9, 30, 0, 0, 0))).assertEqual(14 * HOUR);
      const b = TimeUtil.localDayBounds('Pacific/Kiritimati', 2026, 10, 30);
      expect(b.valid).assertTrue();
      expect(b.startUtc).assertEqual(Date.UTC(2026, 9, 29, 10, 0, 0));
      expect(b.endUtc).assertEqual(Date.UTC(2026, 9, 30, 10, 0, 0));
      expect(b.durationMs).assertEqual(24 * HOUR);
    });

    it('apia_skipped_day_2011_12_30', 0, () => {
      const skipped = TimeUtil.localDayBounds('Pacific/Apia', 2011, 12, 30);
      expect(skipped.valid).assertFalse();
      expect(skipped.kind).assertEqual(DayKind.SKIPPED);
      // 前一天必须正常结束于 12-31 的第一个时刻
      const before = TimeUtil.localDayBounds('Pacific/Apia', 2011, 12, 29);
      expect(before.valid).assertTrue();
      expect(before.endUtc).assertEqual(Date.UTC(2011, 11, 30, 10, 0, 0));
    });

    it('invalid_zone_and_date_are_rejected', 0, () => {
      // 非法时区不得静默当作 UTC
      expect(Number.isNaN(TimeUtil.offsetMs('Not/AZone', Date.UTC(2026, 0, 1)))).assertTrue();
      expect(TimeUtil.isValidTimeZoneId('Not/AZone')).assertFalse();
      expect(TimeUtil.isValidTimeZoneId('Asia/Shanghai')).assertTrue();
      const badBounds = TimeUtil.localDayBounds('Not/AZone', 2026, 10, 30);
      expect(badBounds.valid).assertFalse();
      expect(badBounds.kind).assertEqual(DayKind.INVALID);
      // 2 月 30 日必须被拒绝，不能被规范化成 3 月 2 日
      const badDate = TimeUtil.resolveLocal('Asia/Shanghai', 2026, 2, 30, 10, 0);
      expect(badDate.status).assertEqual(LocalResolveStatus.INVALID);
    });

    it('zone_rules_transition_values_are_real', 0, () => {
      // 直接核验 i18n 跳变对象的真实返回值，确认不是我编的接口
      const rules = i18n.getTimeZone('America/New_York').getZoneRules();
      const transition = rules.nextTransition(Date.UTC(2026, 0, 1, 0, 0, 0));
      expect(transition.getMilliseconds()).assertEqual(Date.UTC(2026, 2, 8, 7, 0, 0));
      expect(transition.getOffsetBefore()).assertEqual(-5 * HOUR);
      expect(transition.getOffsetAfter()).assertEqual(-4 * HOUR);

      // 豪勋爵岛：2026 年第一次跳变是 4 月首个周日「回拨」，+11 → +10:30，差值为 −30 分钟。
      // （原断言写成 +30 分钟是测试预期错误，不是解析实现问题。）
      const lhRules = i18n.getTimeZone('Australia/Lord_Howe').getZoneRules();
      const lhFallBack = lhRules.nextTransition(Date.UTC(2026, 0, 1, 0, 0, 0));
      expect(lhFallBack.getMilliseconds()).assertEqual(Date.UTC(2026, 3, 4, 15, 0, 0));
      expect(lhFallBack.getOffsetBefore()).assertEqual(11 * HOUR);
      expect(lhFallBack.getOffsetAfter()).assertEqual(10 * HOUR + HALF_HOUR);
      expect(lhFallBack.getOffsetAfter() - lhFallBack.getOffsetBefore()).assertEqual(-HALF_HOUR);

      // 同年第二次跳变是 10 月首个周日「前跳」：+10:30 → +11，差值为 +30 分钟。
      const lhSpringForward = lhRules.nextTransition(lhFallBack.getMilliseconds());
      expect(lhSpringForward.getMilliseconds()).assertEqual(Date.UTC(2026, 9, 3, 15, 30, 0));
      expect(lhSpringForward.getOffsetBefore()).assertEqual(10 * HOUR + HALF_HOUR);
      expect(lhSpringForward.getOffsetAfter()).assertEqual(11 * HOUR);
      expect(lhSpringForward.getOffsetAfter() - lhSpringForward.getOffsetBefore()).assertEqual(HALF_HOUR);
    });


    it('timeline_labels_handle_dst_gap_and_overlap', 0, () => {
      // 春季：横轴是 UTC 连续时间，标签由 UTC→本地转换，缺失的 02:xx 不会作为刻度出现
      const spring: TimelineModel = Timeline.fromBounds(Date.UTC(2026, 2, 8, 5, 0, 0),
        Date.UTC(2026, 2, 9, 4, 0, 0));
      expect(spring.valid).assertTrue();
      const springTicks: TimelineTick[] = TimelineLabels.ticks(spring, 'America/New_York', 360);
      expect(springTicks.length > 0).assertTrue();
      for (const t of springTicks) {
        expect(t.label.startsWith('02:')).assertFalse();
        expect(t.ratio >= 0 && t.ratio < 1).assertTrue();
      }
      // 钟表本身确实跳过了 02:xx：07:00Z → 03:00，07:59Z → 03:59
      expect(TimelineLabels.formatLocal(Date.UTC(2026, 2, 8, 7, 0, 0), 'America/New_York')).assertEqual('03:00');
      expect(TimelineLabels.formatLocal(Date.UTC(2026, 2, 8, 6, 59, 0), 'America/New_York')).assertEqual('01:59');

      // 秋季：两个本地 01:30 来自不同 UTC，标签必须能区分（带偏移后缀）
      const first = new TimelineTick();
      first.utcMs = Date.UTC(2026, 10, 1, 5, 30, 0);
      first.label = TimelineLabels.formatLocal(first.utcMs, 'America/New_York');
      const second = new TimelineTick();
      second.utcMs = Date.UTC(2026, 10, 1, 6, 30, 0);
      second.label = TimelineLabels.formatLocal(second.utcMs, 'America/New_York');
      expect(first.label).assertEqual('01:30');
      expect(second.label).assertEqual('01:30');
      const labelled = TimelineLabels.disambiguate([first, second], 'America/New_York');
      expect(labelled[0].label !== labelled[1].label).assertTrue();

      // 半小时时区的短偏移
      expect(TimelineLabels.offsetShort(Date.UTC(2026, 9, 3, 13, 30, 0), 'Australia/Lord_Howe'))
        .assertEqual('+10.5');
    });

    it('start_of_day_and_add_days_follow_real_bounds', 0, () => {
      // 夏令时切换日：startOfLocalDay 必须落在真实起点（当地 00:00 存在时就是它）
      const nySpring = TimeUtil.startOfLocalDay('America/New_York', Date.UTC(2026, 2, 8, 16, 0, 0));
      expect(nySpring).assertEqual(Date.UTC(2026, 2, 8, 5, 0, 0));
      // 次日推进必须跨过 23 小时的一天
      const next = TimeUtil.addLocalDays('America/New_York', nySpring, 1);
      expect(next).assertEqual(Date.UTC(2026, 2, 9, 4, 0, 0));
    });
  });
}
