import { describe, it, expect } from '@ohos/hypium';
import { LightWindow, WindowState } from '../main/ets/services/SolarCalc';
import { ObservationBands } from '../main/ets/services/ObservationBands';

/**
 * UI-1B-R：观测色带必须按 **LightWindow 的显式状态** 判定有效性，
 * 不再用「时间戳是否为负」区分缺失 —— 负 Unix 毫秒是 1970 年以前的合法 UTC 时间。
 */
function win(state: number, gmS: number, gmE: number, geS: number, geE: number,
  bmS: number, bmE: number, beS: number, beE: number, dayValid: boolean): LightWindow {
  const w = new LightWindow();
  w.dayValid = dayValid;
  w.goldenMorningState = state;
  w.goldenEveningState = state;
  w.blueMorningState = state;
  w.blueEveningState = state;
  w.goldenMorningStartUtc = gmS;
  w.goldenMorningEndUtc = gmE;
  w.goldenEveningStartUtc = geS;
  w.goldenEveningEndUtc = geE;
  w.blueMorningStartUtc = bmS;
  w.blueMorningEndUtc = bmE;
  w.blueEveningStartUtc = beS;
  w.blueEveningEndUtc = beE;
  return w;
}

export default function observationBandsTest() {
  describe('ObservationBands', () => {
    it('golden_and_blue_ranges_come_from_real_windows', 0, () => {
      const w = win(WindowState.AVAILABLE, 1000, 2000, 8000, 9000, 900, 1000, 9000, 9500, true);
      expect(ObservationBands.goldenPairs(w).join(',')).assertEqual('1000,2000,8000,9000');
      expect(ObservationBands.bluePairs(w).join(',')).assertEqual('900,1000,9000,9500');
    });

    it('pre_epoch_windows_are_legal_and_kept', 0, () => {
      // 1969-12-31 附近的合法窗口（负时间戳）必须保留
      const w = win(WindowState.AVAILABLE, -20000, -10000, -2000, -1000,
        -30000, -20000, -1000, -500, true);
      expect(ObservationBands.goldenPairs(w).join(',')).assertEqual('-20000,-10000,-2000,-1000');
      expect(ObservationBands.bluePairs(w).join(',')).assertEqual('-30000,-20000,-1000,-500');
    });

    it('cross_epoch_window_is_kept', 0, () => {
      const w = win(WindowState.AVAILABLE, -5000, 5000, -1, -1, -6000, 6000, -1, -1, true);
      expect(ObservationBands.goldenPairs(w).join(',')).assertEqual('-5000,5000');
      expect(ObservationBands.bluePairs(w).join(',')).assertEqual('-6000,6000');
    });

    it('absent_state_is_rejected_even_with_plausible_timestamps', 0, () => {
      // 状态为 ABSENT 时，即使时间戳看起来正常也不能收录（哨兵不靠正负判断）
      const w = win(WindowState.ABSENT, 1000, 2000, 8000, 9000, 900, 1000, 9000, 9500, true);
      expect(ObservationBands.goldenPairs(w).length).assertEqual(0);
      expect(ObservationBands.bluePairs(w).length).assertEqual(0);
    });

    it('day_invalid_state_yields_no_bands', 0, () => {
      const w = win(WindowState.DAY_INVALID, 1000, 2000, 8000, 9000, 900, 1000, 9000, 9500, false);
      expect(ObservationBands.goldenPairs(w).length).assertEqual(0);
      expect(ObservationBands.bluePairs(w).length).assertEqual(0);
    });

    it('reversed_or_zero_length_ranges_are_dropped', 0, () => {
      const w = win(WindowState.AVAILABLE, 2000, 1000, 8000, 8000, 500, 500, 9000, 9500, true);
      expect(ObservationBands.goldenPairs(w).length).assertEqual(0);
      expect(ObservationBands.bluePairs(w).length).assertEqual(2); // 只有黄昏 9000..9500 有效
    });

    it('clipping_uses_real_day_bounds', 0, () => {
      const pairs: number[] = [0, 1000, 5000, 9000];
      const clipped = ObservationBands.clippedPairs(pairs, 500, 8000);
      expect(clipped.join(',')).assertEqual('500,1000,5000,8000');
      expect(ObservationBands.clippedPairs(pairs, 8000, 500).length).assertEqual(0);
    });

    it('clipping_handles_pre_epoch_ranges', 0, () => {
      const pairs: number[] = [-9000, -3000];
      expect(ObservationBands.clippedPairs(pairs, -8000, -1000).join(',')).assertEqual('-8000,-3000');
    });
  });
}
