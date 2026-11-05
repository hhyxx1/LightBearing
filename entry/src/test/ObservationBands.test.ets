import { describe, it, expect } from '@ohos/hypium';
import { LightWindow } from '../main/ets/services/SolarCalc';
import { ObservationBands } from '../main/ets/services/ObservationBands';

/**
 * UI-1B-P：观测仪表色带的纯逻辑测试。
 * 断言只使用真实窗口时间；负值哨兵与非法日必须被丢弃，绝不生成固定比例装饰。
 */
function win(gmS: number, gmE: number, geS: number, geE: number,
  bmS: number, bmE: number, beS: number, beE: number, dayValid: boolean): LightWindow {
  const w = new LightWindow();
  w.goldenMorningStartUtc = gmS;
  w.goldenMorningEndUtc = gmE;
  w.goldenEveningStartUtc = geS;
  w.goldenEveningEndUtc = geE;
  w.blueMorningStartUtc = bmS;
  w.blueMorningEndUtc = bmE;
  w.blueEveningStartUtc = beS;
  w.blueEveningEndUtc = beE;
  w.dayValid = dayValid;
  return w;
}

export default function observationBandsTest() {
  describe('ObservationBands', () => {
    it('golden_and_blue_ranges_come_from_real_windows', 0, () => {
      const w = win(1000, 2000, 8000, 9000, 900, 1000, 9000, 9500, true);
      expect(ObservationBands.goldenPairs(w).join(',')).assertEqual('1000,2000,8000,9000');
      expect(ObservationBands.bluePairs(w).join(',')).assertEqual('900,1000,9000,9500');
    });

    it('missing_windows_are_skipped_not_faked', 0, () => {
      // -1 哨兵（极昼/极夜/无穿越）必须被丢弃，不能生成装饰性区间
      const w = win(-1, -1, -1, -1, 900, 1000, -1, -1, true);
      expect(ObservationBands.goldenPairs(w).length).assertEqual(0);
      expect(ObservationBands.bluePairs(w).join(',')).assertEqual('900,1000');
    });

    it('invalid_day_yields_no_bands', 0, () => {
      const w = win(1000, 2000, 8000, 9000, 900, 1000, 9000, 9500, false);
      expect(ObservationBands.goldenPairs(w).length).assertEqual(0);
      expect(ObservationBands.bluePairs(w).length).assertEqual(0);
    });

    it('reversed_or_zero_length_ranges_are_dropped', 0, () => {
      const w = win(2000, 1000, 8000, 8000, 900, 1000, 9000, 9500, true);
      expect(ObservationBands.goldenPairs(w).length).assertEqual(0);
    });

    it('clipping_uses_real_day_bounds', 0, () => {
      // 跨日边界的窗口按真实日界裁剪，不做固定比例
      const pairs: number[] = [0, 1000, 5000, 9000];
      const clipped = ObservationBands.clippedPairs(pairs, 500, 8000);
      expect(clipped.join(',')).assertEqual('500,1000,5000,8000');
      expect(ObservationBands.clippedPairs(pairs, 8000, 500).length).assertEqual(0);
    });
  });
}
