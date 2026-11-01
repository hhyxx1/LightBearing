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

/** 探针「声明有效」但拿不到任何偏移数据（模拟时区数据库故障） */
class NaNProbe implements ZoneProbe {
  isValid(): boolean {
    return true;
  }

  offsetAt(utcMs: number): number {
    return NaN;
  }

  transitionAfter(utcMs: number): ZoneTransitionInfo | undefined {
    return undefined;
  }
}

/** 只在候选时刻附近返回 NaN 的探针（模拟候选校验阶段查询失败） */
class CandidateNaNProbe implements ZoneProbe {
  private inner: ZoneProbe;
  private fromUtc: number;
  private toUtc: number;

  constructor(inner: ZoneProbe, fromUtc: number, toUtc: number) {
    this.inner = inner;
    this.fromUtc = fromUtc;
    this.toUtc = toUtc;
  }

  isValid(): boolean {
    return true;
  }

  offsetAt(utcMs: number): number {
    if (utcMs >= this.fromUtc && utcMs <= this.toUtc) {
      return NaN;
    }
    return this.inner.offsetAt(utcMs);
  }

  transitionAfter(utcMs: number): ZoneTransitionInfo | undefined {
    return this.inner.transitionAfter(utcMs);
  }
}

/** 拿不到跳变表（transitionAfter 恒为 undefined）但偏移正确的探针 */
class NoTransitionProbe implements ZoneProbe {
  private inner: ZoneProbe;

  constructor(inner: ZoneProbe) {
    this.inner = inner;
  }

  isValid(): boolean {
    return true;
  }

  offsetAt(utcMs: number): number {
    return this.inner.offsetAt(utcMs);
  }

  transitionAfter(utcMs: number): ZoneTransitionInfo | undefined {
    return undefined;
  }
}

/**
 * 有缺口但跳变表给不出对应跳变的探针：
 * offsetAt 在 2026-03-08T07:00Z 前跳（-5h → -4h），resolve 会判定 GAP；
 * 但 transitionAfter 只返回一次与缺口无关的回拨跳变。
 * 用于验证 fromLocal 兼容接口不会拿不相关的跳变当缺口结束。
 */
class GapWithoutMatchingTransitionProbe implements ZoneProbe {
  private gapProbe: ZoneProbe = newYorkLike();
  private unrelated: ZoneTransitionInfo =
    ZoneTransitionInfo.of(Date.UTC(2026, 10, 1, 6, 0, 0), -4 * HOUR, -5 * HOUR);

  isValid(): boolean {
    return true;
  }

  offsetAt(utcMs: number): number {
    return this.gapProbe.offsetAt(utcMs);
  }

  transitionAfter(utcMs: number): ZoneTransitionInfo | undefined {
    return utcMs < this.unrelated.atUtc ? this.unrelated : undefined;
  }
}

/** 只有回拨跳变（offsetAfter < offsetBefore）的时区：不可能造成缺口 */
function onlyFallBackZone(): ZoneProbe {
  const transitions: ZoneTransitionInfo[] = [
    ZoneTransitionInfo.of(Date.UTC(2026, 10, 1, 6, 0, 0), -4 * HOUR, -5 * HOUR)
  ];
  return new SyntheticZone(-5 * HOUR, transitions);
}

/**
 * 极端构造：本地 2026-05-01 只存在 01:00–04:00（3 小时）。
 * t1 2026-05-01T00:00Z：0 → +1h（00:00–01:00 缺失）
 * t2 2026-05-01T03:00Z：+1h → +25h（04:00 之后直接进入 05-02）
 * 旧实现在 00:00 缺口时会抽样 6/12/18/23 点，全部落在 05-02，从而误判整日 SKIPPED。
 */
function shortWindowZone(): ZoneProbe {
  const transitions: ZoneTransitionInfo[] = [
    ZoneTransitionInfo.of(Date.UTC(2026, 4, 1, 0, 0, 0), 0, HOUR),
    ZoneTransitionInfo.of(Date.UTC(2026, 4, 1, 3, 0, 0), HOUR, 25 * HOUR)
  ];
  return new SyntheticZone(0, transitions);
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

    it('zero_offset_is_valid_not_failure', 0, () => {
      // UTC+00:00 的偏移 0 是合法值，不能被当成探针失败
      const utcZone = new SyntheticZone(0, []);
      const r = LocalTimeResolver.resolve(utcZone, 2026, 10, 30, 12, 0);
      expect(r.status).assertEqual(LocalResolveStatus.UNIQUE);
      expect(r.candidatesUtc[0]).assertEqual(Date.UTC(2026, 9, 30, 12, 0, 0));
      expect(r.candidateOffsets[0]).assertEqual(0);
      const b = LocalTimeResolver.dayBounds(utcZone, 2026, 10, 30);
      expect(b.valid).assertTrue();
      expect(b.durationMs).assertEqual(24 * HOUR);
    });

    it('probe_data_unavailable_is_not_gap', 0, () => {
      // 探针声明有效但拿不到偏移：必须是 UNAVAILABLE，不能报「时间不存在」
      const r = LocalTimeResolver.resolve(new NaNProbe(), 2026, 10, 30, 12, 0);
      expect(r.status).assertEqual(LocalResolveStatus.UNAVAILABLE);
      expect(r.status === LocalResolveStatus.GAP).assertFalse();
      expect(r.candidatesUtc.length).assertEqual(0);

      const b = LocalTimeResolver.dayBounds(new NaNProbe(), 2026, 10, 30);
      expect(b.valid).assertFalse();
      expect(b.kind).assertEqual(DayKind.INVALID);
      expect(b.kind === DayKind.SKIPPED).assertFalse();
    });

    it('candidate_verification_failure_is_unavailable', 0, () => {
      // 候选校验阶段 offsetAt 返回 NaN：同样不能报 GAP
      const target = Date.UTC(2026, 9, 30, 12, 0, 0);
      const probe = new CandidateNaNProbe(new SyntheticZone(8 * HOUR, []),
        target - 8 * HOUR - HOUR, target - 8 * HOUR + HOUR);
      const r = LocalTimeResolver.resolve(probe, 2026, 10, 30, 12, 0);
      expect(r.status).assertEqual(LocalResolveStatus.UNAVAILABLE);
    });

    it('real_gap_and_overlap_still_reported', 0, () => {
      // 修复不得改变真实缺口/重复的判定
      expect(LocalTimeResolver.resolve(newYorkLike(), 2026, 3, 8, 2, 30).status)
        .assertEqual(LocalResolveStatus.GAP);
      expect(LocalTimeResolver.resolve(newYorkLike(), 2026, 11, 1, 1, 30).status)
        .assertEqual(LocalResolveStatus.OVERLAP);
    });

    it('compat_fromLocal_gap_returns_gap_end', 0, () => {
      // 纽约春季 02:30：缺口结束（本地 03:00）对应 UTC 07:00Z
      const utc = LocalTimeResolver.toUtcCompat(newYorkLike(), 2026, 3, 8, 2, 30);
      expect(utc).assertEqual(Date.UTC(2026, 2, 8, 7, 0, 0));
      // 换算回本地必须是 03:00，而不是被悄悄平移成 01:30
      const local = new Date(utc - 4 * HOUR);
      expect(local.getUTCHours()).assertEqual(3);
      expect(local.getUTCMinutes()).assertEqual(0);
    });

    it('compat_fromLocal_half_hour_gap', 0, () => {
      // 豪勋爵 02:15 缺口 → 缺口结束是本地 02:30
      const utc = LocalTimeResolver.toUtcCompat(lordHoweLike(), 2026, 10, 4, 2, 15);
      expect(utc).assertEqual(Date.UTC(2026, 9, 3, 15, 30, 0));
      const local = new Date(utc + 11 * HOUR);
      expect(local.getUTCHours()).assertEqual(2);
      expect(local.getUTCMinutes()).assertEqual(30);
    });

    it('compat_fromLocal_skipped_day', 0, () => {
      // 阿皮亚整日跳过：12-30 落在 24 小时缺口内，缺口结束为 12-31 00:00
      const utc = LocalTimeResolver.toUtcCompat(apiaLike(), 2011, 12, 30, 12, 0);
      expect(utc).assertEqual(Date.UTC(2011, 11, 30, 10, 0, 0));
      const local = new Date(utc + 14 * HOUR);
      expect(local.getUTCFullYear()).assertEqual(2011);
      expect(local.getUTCMonth() + 1).assertEqual(12);
      expect(local.getUTCDate()).assertEqual(31);
      expect(local.getUTCHours()).assertEqual(0);
    });

    it('compat_fromLocal_normal_and_overlap', 0, () => {
      // 普通时间：唯一候选
      expect(LocalTimeResolver.toUtcCompat(new SyntheticZone(8 * HOUR, []), 2026, 10, 30, 12, 0))
        .assertEqual(Date.UTC(2026, 9, 30, 4, 0, 0));
      // 重复时间：取较早一次
      expect(LocalTimeResolver.toUtcCompat(newYorkLike(), 2026, 11, 1, 1, 30))
        .assertEqual(Date.UTC(2026, 10, 1, 5, 30, 0));
    });

    it('compat_fromLocal_never_guesses_without_matching_transition', 0, () => {
      // 探针故障 → NaN
      expect(Number.isNaN(LocalTimeResolver.toUtcCompat(new NaNProbe(), 2026, 3, 8, 2, 30))).assertTrue();
      // 缺口存在但跳变表里没有对应那次前跳 → 不能随便返回某个时间
      expect(Number.isNaN(
        LocalTimeResolver.toUtcCompat(new GapWithoutMatchingTransitionProbe(), 2026, 3, 8, 2, 30))).assertTrue();
      // 非法日期 → NaN
      expect(Number.isNaN(LocalTimeResolver.toUtcCompat(newYorkLike(), 2026, 2, 30, 2, 30))).assertTrue();
    });

    it('resolver_works_without_transition_info', 0, () => {
      // transitionAfter 永远返回 undefined（拿不到跳变表）时，靠三处偏移采样仍要正确
      const noTransitions = new SyntheticZone(-5 * HOUR, []);
      // 构造一个「只有回拨」的探针，但 transitionAfter 返回 undefined
      const probe: ZoneProbe = new NoTransitionProbe(newYorkLike());
      expect(LocalTimeResolver.resolve(probe, 2026, 11, 1, 1, 30).status)
        .assertEqual(LocalResolveStatus.OVERLAP);
      expect(LocalTimeResolver.resolve(noTransitions, 2026, 10, 30, 12, 0).status)
        .assertEqual(LocalResolveStatus.UNIQUE);
    });

    it('short_valid_window_day_is_not_marked_skipped', 0, () => {
      // 该本地日只有 01:00–04:00 存在；抽样 6/12/18/23 点会全部落空
      const b = LocalTimeResolver.dayBounds(shortWindowZone(), 2026, 5, 1);
      expect(b.valid).assertTrue();
      expect(b.kind).assertEqual(DayKind.SHORT);
      expect(b.startUtc).assertEqual(Date.UTC(2026, 4, 1, 0, 0, 0));
      expect(b.endUtc).assertEqual(Date.UTC(2026, 4, 1, 3, 0, 0));
      expect(b.durationMs).assertEqual(3 * HOUR);
    });

    it('add_local_days_skips_skipped_calendar_day', 0, () => {
      // 从 2011-12-29 前进 1 天：12-30 整日不存在，应自动落到 12-31 的起点
      expect(LocalTimeResolver.addLocalDayStart(apiaLike(), 2011, 12, 29, 1))
        .assertEqual(Date.UTC(2011, 11, 30, 10, 0, 0));
      // 后退一天同样正确
      expect(LocalTimeResolver.addLocalDayStart(apiaLike(), 2011, 12, 31, -1))
        .assertEqual(Date.UTC(2011, 11, 29, 10, 0, 0));
      // 普通时区 +1 天
      expect(LocalTimeResolver.addLocalDayStart(new SyntheticZone(8 * HOUR, []), 2026, 10, 30, 1))
        .assertEqual(Date.UTC(2026, 9, 30, 16, 0, 0));
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
