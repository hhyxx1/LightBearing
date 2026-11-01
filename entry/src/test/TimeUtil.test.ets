import { describe, it, expect } from '@ohos/hypium';
import {
  DayKind, LocalDayBounds, LocalResolveResult, LocalResolveStatus, LocalTimeResolver,
  ZoneProbe, ZoneTransitionInfo
} from '../main/ets/services/LocalTimeResolver';

/**
 * 时区解析核心的宿主机测试。
 *
 * 为什么用「合成时区」：宿主机单测环境里的 @kit.LocalizationKit 是空实现
 * （实测 getID() 返回空串、getOffset() 返回 0），真实 IANA 数据只能在设备上验证
 * （见 entry/src/ohosTest/ets/test/TimeZoneReal.test.ets）。
 * 这里注入固定规则的合成时区，验证 GAP / OVERLAP / 23h / 25h / 23.5h / 24.5h /
 * 整日跳过 / 无效输入 等算法行为，期望值全部是手算的固定 UTC 常量。
 */

const HOUR: number = 3600000.0;
const HALF_HOUR: number = 1800000.0;

/** 合成时区：基础偏移 + 若干跳变 */
class SyntheticZone implements ZoneProbe {
  private baseOffset: number = 0;
  private transitions: ZoneTransitionInfo[] = [];
  private valid: boolean = true;

  constructor(baseOffset: number, transitions: ZoneTransitionInfo[], valid: boolean = true) {
    this.baseOffset = baseOffset;
    this.transitions = transitions;
    this.valid = valid;
  }

  isValid(): boolean {
    return this.valid;
  }

  offsetAt(utcMs: number): number {
    if (!this.valid) {
      return NaN;
    }
    let offset = this.baseOffset;
    for (const t of this.transitions) {
      if (utcMs >= t.atUtc) {
        offset = t.offsetAfter;
      }
    }
    return offset;
  }

  transitionAfter(utcMs: number): ZoneTransitionInfo | undefined {
    if (!this.valid) {
      return undefined;
    }
    for (const t of this.transitions) {
      if (t.atUtc > utcMs) {
        return t;
      }
    }
    return undefined;
  }
}

/** 纽约式：春季 2026-03-08T07:00Z 由 −5 跳到 −4；秋季 2026-11-01T06:00Z 由 −4 回拨到 −5 */
function newYorkLike(): ZoneProbe {
  const transitions: ZoneTransitionInfo[] = [
    ZoneTransitionInfo.of(Date.UTC(2026, 2, 8, 7, 0, 0), -5 * HOUR, -4 * HOUR),
    ZoneTransitionInfo.of(Date.UTC(2026, 10, 1, 6, 0, 0), -4 * HOUR, -5 * HOUR)
  ];
  return new SyntheticZone(-5 * HOUR, transitions);
}

/** 豪勋爵岛式：半小时夏令时。2026-04-04T15:00Z 回拨（+11→+10:30）；2026-10-03T15:30Z 前跳（+10:30→+11） */
function lordHoweLike(): ZoneProbe {
  const transitions: ZoneTransitionInfo[] = [
    ZoneTransitionInfo.of(Date.UTC(2026, 3, 4, 15, 0, 0), 11 * HOUR, 10 * HOUR + HALF_HOUR),
    ZoneTransitionInfo.of(Date.UTC(2026, 9, 3, 15, 30, 0), 10 * HOUR + HALF_HOUR, 11 * HOUR)
  ];
  return new SyntheticZone(11 * HOUR, transitions);
}

/** 阿皮亚式：2011-12-30T10:00Z 由 −10 直接跳到 +14，整日 2011-12-30 不存在 */
function apiaLike(): ZoneProbe {
  const transitions: ZoneTransitionInfo[] = [
    ZoneTransitionInfo.of(Date.UTC(2011, 11, 30, 10, 0, 0), -10 * HOUR, 14 * HOUR)
  ];
  return new SyntheticZone(-10 * HOUR, transitions);
}

export default function timeUtilTest() {
  describe('LocalTimeResolver', () => {
    it('north_america_spring_forward_23h_day', 0, () => {
      const b: LocalDayBounds = LocalTimeResolver.dayBounds(newYorkLike(), 2026, 3, 8);
      expect(b.valid).assertTrue();
      expect(b.startUtc).assertEqual(Date.UTC(2026, 2, 8, 5, 0, 0));
      expect(b.endUtc).assertEqual(Date.UTC(2026, 2, 9, 4, 0, 0));
      expect(b.durationMs).assertEqual(23 * HOUR);
      expect(b.kind).assertEqual(DayKind.SHORT);
    });

    it('north_america_spring_forward_gap', 0, () => {
      const r: LocalResolveResult = LocalTimeResolver.resolve(newYorkLike(), 2026, 3, 8, 2, 30);
      expect(r.status).assertEqual(LocalResolveStatus.GAP);
      expect(r.candidatesUtc.length).assertEqual(0);
    });

    it('north_america_spring_forward_edges', 0, () => {
      const before = LocalTimeResolver.resolve(newYorkLike(), 2026, 3, 8, 1, 30);
      expect(before.status).assertEqual(LocalResolveStatus.UNIQUE);
      expect(before.candidatesUtc[0]).assertEqual(Date.UTC(2026, 2, 8, 6, 30, 0));
      expect(before.candidateOffsets[0]).assertEqual(-5 * HOUR);

      const after = LocalTimeResolver.resolve(newYorkLike(), 2026, 3, 8, 3, 30);
      expect(after.status).assertEqual(LocalResolveStatus.UNIQUE);
      expect(after.candidatesUtc[0]).assertEqual(Date.UTC(2026, 2, 8, 7, 30, 0));
      expect(after.candidateOffsets[0]).assertEqual(-4 * HOUR);
    });

    it('north_america_fall_back_25h_day', 0, () => {
      const b = LocalTimeResolver.dayBounds(newYorkLike(), 2026, 11, 1);
      expect(b.valid).assertTrue();
      expect(b.startUtc).assertEqual(Date.UTC(2026, 10, 1, 4, 0, 0));
      expect(b.endUtc).assertEqual(Date.UTC(2026, 10, 2, 5, 0, 0));
      expect(b.durationMs).assertEqual(25 * HOUR);
      expect(b.kind).assertEqual(DayKind.LONG);
    });

    it('north_america_fall_back_overlap_two_candidates', 0, () => {
      const r = LocalTimeResolver.resolve(newYorkLike(), 2026, 11, 1, 1, 30);
      expect(r.status).assertEqual(LocalResolveStatus.OVERLAP);
      expect(r.candidatesUtc.length).assertEqual(2);
      // 必须按 UTC 升序
      expect(r.candidatesUtc[0]).assertEqual(Date.UTC(2026, 10, 1, 5, 30, 0));
      expect(r.candidatesUtc[1]).assertEqual(Date.UTC(2026, 10, 1, 6, 30, 0));
      expect(r.candidateOffsets[0]).assertEqual(-4 * HOUR);
      expect(r.candidateOffsets[1]).assertEqual(-5 * HOUR);
    });

    it('half_hour_dst_short_and_long_days', 0, () => {
      const short = LocalTimeResolver.dayBounds(lordHoweLike(), 2026, 10, 4);
      expect(short.valid).assertTrue();
      expect(short.durationMs).assertEqual(23 * HOUR + HALF_HOUR);
      expect(short.kind).assertEqual(DayKind.SHORT);

      const long = LocalTimeResolver.dayBounds(lordHoweLike(), 2026, 4, 5);
      expect(long.valid).assertTrue();
      expect(long.durationMs).assertEqual(24 * HOUR + HALF_HOUR);
      expect(long.kind).assertEqual(DayKind.LONG);
    });

    it('half_hour_dst_gap_and_overlap', 0, () => {
      const gap = LocalTimeResolver.resolve(lordHoweLike(), 2026, 10, 4, 2, 15);
      expect(gap.status).assertEqual(LocalResolveStatus.GAP);

      const overlap = LocalTimeResolver.resolve(lordHoweLike(), 2026, 4, 5, 1, 45);
      expect(overlap.status).assertEqual(LocalResolveStatus.OVERLAP);
      expect(overlap.candidatesUtc.length).assertEqual(2);
      // 两次候选相差恰好半小时
      expect(overlap.candidatesUtc[1] - overlap.candidatesUtc[0]).assertEqual(HALF_HOUR);
    });

    it('skipped_calendar_day_is_invalid_not_remapped', 0, () => {
      const skipped = LocalTimeResolver.dayBounds(apiaLike(), 2011, 12, 30);
      expect(skipped.valid).assertFalse();
      expect(skipped.kind).assertEqual(DayKind.SKIPPED);
      expect(skipped.startUtc).assertEqual(-1);
    });

    it('day_before_skipped_day_ends_at_next_existing_midnight', 0, () => {
      const b = LocalTimeResolver.dayBounds(apiaLike(), 2011, 12, 29);
      expect(b.valid).assertTrue();
      expect(b.startUtc).assertEqual(Date.UTC(2011, 11, 29, 10, 0, 0));
      // 12-30 整日不存在，结束边界应落到 12-31 00:00 本地（= 12-30T10:00Z）
      expect(b.endUtc).assertEqual(Date.UTC(2011, 11, 30, 10, 0, 0));
      expect(b.durationMs).assertEqual(24 * HOUR);
    });

    it('invalid_inputs_are_rejected', 0, () => {
      expect(LocalTimeResolver.isValidDate(2026, 2, 30)).assertFalse();
      expect(LocalTimeResolver.isValidDate(2026, 13, 1)).assertFalse();
      expect(LocalTimeResolver.isValidDate(2026, 0, 1)).assertFalse();
      expect(LocalTimeResolver.isValidDate(2026, 4, 31)).assertFalse();
      expect(LocalTimeResolver.isValidDate(2024, 2, 29)).assertTrue();

      const badDate = LocalTimeResolver.resolve(newYorkLike(), 2026, 2, 30, 12, 0);
      expect(badDate.status).assertEqual(LocalResolveStatus.INVALID);

      const badTime = LocalTimeResolver.resolve(newYorkLike(), 2026, 3, 8, 24, 0);
      expect(badTime.status).assertEqual(LocalResolveStatus.INVALID);

      const badZone = LocalTimeResolver.resolve(new SyntheticZone(0, [], false), 2026, 3, 8, 12, 0);
      expect(badZone.status).assertEqual(LocalResolveStatus.INVALID);

      const badBounds = LocalTimeResolver.dayBounds(newYorkLike(), 2026, 2, 30);
      expect(badBounds.valid).assertFalse();
      expect(badBounds.kind).assertEqual(DayKind.INVALID);
    });

    it('leap_year_and_month_lengths', 0, () => {
      expect(LocalTimeResolver.isLeapYear(2024)).assertTrue();
      expect(LocalTimeResolver.isLeapYear(1900)).assertFalse();
      expect(LocalTimeResolver.isLeapYear(2000)).assertTrue();
      expect(LocalTimeResolver.daysInMonth(2026, 2)).assertEqual(28);
      expect(LocalTimeResolver.daysInMonth(2024, 2)).assertEqual(29);
      expect(LocalTimeResolver.daysInMonth(2026, 12)).assertEqual(31);
    });

    it('utc_roundtrip_is_stable_for_unique_times', 0, () => {
      // 固定 +8 时区，抽样 4 个本地时间做「本地 → UTC → 本地」往返
      const plus8 = new SyntheticZone(8 * HOUR, []);
      const samples: number[][] = [[2026, 10, 30, 0, 0], [2026, 10, 30, 6, 15], [2026, 12, 31, 23, 59]];
      for (const s of samples) {
        const r = LocalTimeResolver.resolve(plus8, s[0], s[1], s[2], s[3], s[4]);
        expect(r.status).assertEqual(LocalResolveStatus.UNIQUE);
        const local = new Date(r.candidatesUtc[0] + r.candidateOffsets[0]);
        expect(local.getUTCFullYear()).assertEqual(s[0]);
        expect(local.getUTCMonth() + 1).assertEqual(s[1]);
        expect(local.getUTCDate()).assertEqual(s[2]);
        expect(local.getUTCHours()).assertEqual(s[3]);
        expect(local.getUTCMinutes()).assertEqual(s[4]);
      }
    });

    it('year_boundary_and_month_end', 0, () => {
      const plus8 = new SyntheticZone(8 * HOUR, []);
      // 跨年：2026-12-31 → 2027-01-01
      const dec31 = LocalTimeResolver.dayBounds(plus8, 2026, 12, 31);
      expect(dec31.valid).assertTrue();
      expect(dec31.startUtc).assertEqual(Date.UTC(2026, 11, 30, 16, 0, 0));
      expect(dec31.endUtc).assertEqual(Date.UTC(2026, 11, 31, 16, 0, 0));
      // 月末：2026-02-28 → 2026-03-01
      const feb28 = LocalTimeResolver.dayBounds(plus8, 2026, 2, 28);
      expect(feb28.endUtc - feb28.startUtc).assertEqual(24 * HOUR);
      const nextDate = LocalTimeResolver.plusOneDay(2024, 2, 28);
      expect(nextDate[0]).assertEqual(2024);
      expect(nextDate[1]).assertEqual(2);
      expect(nextDate[2]).assertEqual(29);
    });
  });
}
