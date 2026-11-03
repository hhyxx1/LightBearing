import { describe, it, expect } from '@ohos/hypium';
import { PlanPlaceGuard, EditPlaceContext, SavePlaceOutcome, PlaceSnapshot } from '../main/ets/services/PlanPlaceGuard';
import { Place, ShootPlan } from '../main/ets/model/Models';

/**
 * QA-2A / QA-03 回归：计划与机位关系守卫。
 * 覆盖「原机位存在 / 缺失 / 机位列表为空 / 明确换机位」四类场景，并验证保存路径
 * （applyPlace）不会静默改写 placeId、坐标、时区、计划 ID 与已保存的 UTC。
 */

function place(id: string, name: string, lat: number, lon: number, tz: string): Place {
  const p = new Place();
  p.id = id;
  p.name = name;
  p.latWgs84 = lat;
  p.lonWgs84 = lon;
  p.tzId = tz;
  return p;
}

function planWith(placeId: string, name: string, lat: number, lon: number, tz: string,
  utc: number): ShootPlan {
  const p = new ShootPlan();
  p.id = 'plan-1';
  p.placeId = placeId;
  p.placeName = name;
  p.latWgs84 = lat;
  p.lonWgs84 = lon;
  p.tzId = tz;
  p.selectedUtc = utc;
  p.note = '原备注';
  p.targetAzimuth = 180;
  p.targetAltitude = 10;
  return p;
}

const UTC0: number = Date.UTC(2026, 9, 30, 9, 30, 0);

export default function planPlaceGuardTest() {
  describe('PlanPlaceGuard', () => {
    it('edit_matches_place_by_id_not_index', 0, () => {
      const places: Place[] = [
        place('a', '上海', 31.2304, 121.4737, 'Asia/Shanghai'),
        place('b', '纽约', 40.7128, -74.006, 'America/New_York')
      ];
      const plan = planWith('b', '纽约', 40.7128, -74.006, 'America/New_York', UTC0);
      const ctx: EditPlaceContext = PlanPlaceGuard.resolveEdit(places, plan);
      expect(ctx.detached).assertFalse();
      expect(ctx.matchedIndex).assertEqual(1);
      expect(ctx.note.length).assertEqual(0);
    });

    it('edit_detached_keeps_original_snapshot', 0, () => {
      const places: Place[] = [place('a', '上海', 31.2304, 121.4737, 'Asia/Shanghai')];
      const plan = planWith('gone', '已删机位', 12.34, 56.78, 'Pacific/Apia', UTC0);
      const ctx = PlanPlaceGuard.resolveEdit(places, plan);
      expect(ctx.detached).assertTrue();
      expect(ctx.matchedIndex).assertEqual(-1);
      expect(ctx.snapshot.placeId).assertEqual('gone');
      expect(ctx.snapshot.placeName).assertEqual('已删机位');
      expect(ctx.snapshot.latWgs84).assertEqual(12.34);
      expect(ctx.snapshot.lonWgs84).assertEqual(56.78);
      expect(ctx.snapshot.tzId).assertEqual('Pacific/Apia');
      expect(ctx.note.indexOf('已删除') >= 0).assertTrue();
    });

    it('save_without_explicit_change_never_rewrites_place_fields', 0, () => {
      // 核心数据保护：孤立计划保存时，placeId/坐标/时区/ID/UTC 全部保持原值
      const places: Place[] = [place('a', '上海', 31.2304, 121.4737, 'Asia/Shanghai')];
      const plan = planWith('gone', '已删机位', 12.34, 56.78, 'Pacific/Apia', UTC0);
      const ctx = PlanPlaceGuard.resolveEdit(places, plan);
      const outcome: SavePlaceOutcome = PlanPlaceGuard.resolveSave(ctx, 0, places, false);
      expect(outcome.ok).assertTrue();
      expect(outcome.useSnapshot).assertTrue();
      PlanPlaceGuard.applyPlace(plan, outcome);
      expect(plan.placeId).assertEqual('gone');
      expect(plan.placeName).assertEqual('已删机位');
      expect(plan.latWgs84).assertEqual(12.34);
      expect(plan.lonWgs84).assertEqual(56.78);
      expect(plan.tzId).assertEqual('Pacific/Apia');
      expect(plan.id).assertEqual('plan-1');
      expect(plan.selectedUtc).assertEqual(UTC0);
      expect(plan.note).assertEqual('原备注');
    });

    it('save_detached_with_empty_places_still_uses_snapshot', 0, () => {
      const places: Place[] = [];
      const plan = planWith('gone', '已删机位', 12.34, 56.78, 'Pacific/Apia', UTC0);
      const ctx = PlanPlaceGuard.resolveEdit(places, plan);
      const outcome = PlanPlaceGuard.resolveSave(ctx, -1, places, false);
      expect(outcome.ok).assertTrue();
      expect(outcome.useSnapshot).assertTrue();
      PlanPlaceGuard.applyPlace(plan, outcome);
      expect(plan.placeId).assertEqual('gone');
    });

    it('explicit_change_writes_new_place_and_keeps_utc_and_id', 0, () => {
      const places: Place[] = [
        place('a', '上海', 31.2304, 121.4737, 'Asia/Shanghai'),
        place('b', '纽约', 40.7128, -74.006, 'America/New_York')
      ];
      const plan = planWith('gone', '已删机位', 12.34, 56.78, 'Pacific/Apia', UTC0);
      const ctx = PlanPlaceGuard.resolveEdit(places, plan);
      const outcome = PlanPlaceGuard.resolveSave(ctx, 1, places, true);
      expect(outcome.ok).assertTrue();
      expect(outcome.useSnapshot).assertFalse();
      expect(outcome.notice.length > 0).assertTrue();
      PlanPlaceGuard.applyPlace(plan, outcome);
      expect(plan.placeId).assertEqual('b');
      expect(plan.placeName).assertEqual('纽约');
      expect(plan.tzId).assertEqual('America/New_York');
      // UTC 与 ID 不因换机位而改变
      expect(plan.selectedUtc).assertEqual(UTC0);
      expect(plan.id).assertEqual('plan-1');
    });

    it('explicit_change_without_available_place_is_blocked', 0, () => {
      const places: Place[] = [];
      const plan = planWith('gone', '已删机位', 12.34, 56.78, 'Pacific/Apia', UTC0);
      const ctx = PlanPlaceGuard.resolveEdit(places, plan);
      const outcome = PlanPlaceGuard.resolveSave(ctx, -1, places, true);
      expect(outcome.ok).assertFalse();
      expect(outcome.reason.length > 0).assertTrue();
      PlanPlaceGuard.applyPlace(plan, outcome);
      // 被拒绝时不得留下任何改动
      expect(plan.placeId).assertEqual('gone');
      expect(plan.latWgs84).assertEqual(12.34);
    });

    it('matched_plan_without_selection_is_blocked', 0, () => {
      const places: Place[] = [place('a', '上海', 31.2304, 121.4737, 'Asia/Shanghai')];
      const plan = planWith('a', '上海', 31.2304, 121.4737, 'Asia/Shanghai', UTC0);
      const ctx = PlanPlaceGuard.resolveEdit(places, plan);
      const outcome = PlanPlaceGuard.resolveSave(ctx, -1, places, false);
      expect(outcome.ok).assertFalse();
      expect(outcome.reason.indexOf('请先选择机位') >= 0).assertTrue();
    });

    it('matched_plan_normal_save_keeps_values', 0, () => {
      const places: Place[] = [place('a', '上海', 31.2304, 121.4737, 'Asia/Shanghai')];
      const plan = planWith('a', '上海', 31.2304, 121.4737, 'Asia/Shanghai', UTC0);
      const ctx = PlanPlaceGuard.resolveEdit(places, plan);
      const outcome = PlanPlaceGuard.resolveSave(ctx, 0, places, false);
      expect(outcome.ok).assertTrue();
      expect(outcome.useSnapshot).assertFalse();
      expect(outcome.notice.length).assertEqual(0);
      PlanPlaceGuard.applyPlace(plan, outcome);
      expect(plan.placeId).assertEqual('a');
      expect(plan.selectedUtc).assertEqual(UTC0);
    });
  });
}
