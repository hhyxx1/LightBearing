import { Place, ShootPlan } from '../model/Models';

/** 计划内保存的机位快照（机位被删除后仍能还原的原始信息） */
export class PlaceSnapshot {
  placeId: string = '';
  placeName: string = '';
  latWgs84: number = 0;
  lonWgs84: number = 0;
  tzId: string = '';
}

/** 编辑计划时的机位解析结果 */
export class EditPlaceContext {
  /** 精确匹配到的机位下标；-1 表示未匹配（原机位已删除） */
  matchedIndex: number = -1;
  /** 原机位是否已删除（孤立计划） */
  detached: boolean = false;
  /** 计划自带的机位快照 */
  snapshot: PlaceSnapshot = new PlaceSnapshot();
  /** 展示给用户的说明 */
  note: string = '';
}

/** 保存时应当写入的机位信息 */
export class SavePlaceOutcome {
  ok: boolean = true;
  reason: string = '';
  /** true = 保留计划原有机位快照，不写任何机位字段 */
  useSnapshot: boolean = false;
  /** 需要提示用户的信息（例如"计划所属地点已更改"） */
  notice: string = '';
  effective: PlaceSnapshot = new PlaceSnapshot();
}

/**
 * QA-2A / QA-03：计划与机位关系的守卫（纯逻辑，便于测试）。
 *
 * 规则：
 * 1. 编辑已有计划必须按 placeId **精确匹配**，匹配失败不得回退到索引 0；
 * 2. 原机位缺失（孤立计划）时，保存沿用计划自带的机位快照，绝不静默改写到别的机位；
 * 3. 只有用户明确选择了新机位，才允许改写计划的机位字段，并给出提示；
 * 4. 机位列表为空且用户仍要求换机位 → 拒绝保存并说明原因。
 */
export class PlanPlaceGuard {
  /**
   * 保存前的一致性检查：编辑已有计划时，如果记录已不存在，必须中止而不是静默重建。
   * @param editId 正在编辑的计划 ID（空串表示新建）
   * @param found 数据库中是否仍能读到该计划
   * @returns 空串表示可以继续；否则为需要提示用户的原因
   */
  static requireExistingPlan(editId: string, found: boolean): string {
    if (editId.length > 0 && !found) {
      return '该计划已被删除或不存在，无法保存。请返回列表刷新后重试。';
    }
    return '';
  }

  static resolveEdit(places: Place[], plan: ShootPlan): EditPlaceContext {
    const ctx = new EditPlaceContext();
    ctx.snapshot.placeId = plan.placeId;
    ctx.snapshot.placeName = plan.placeName;
    ctx.snapshot.latWgs84 = plan.latWgs84;
    ctx.snapshot.lonWgs84 = plan.lonWgs84;
    ctx.snapshot.tzId = plan.tzId;
    for (let i = 0; i < places.length; i++) {
      if (places[i].id === plan.placeId) {
        ctx.matchedIndex = i;
        ctx.detached = false;
        ctx.note = '';
        return ctx;
      }
    }
    ctx.matchedIndex = -1;
    ctx.detached = true;
    ctx.note = `此计划关联的机位已删除（原机位「${plan.placeName}」` +
      ` ${plan.latWgs84.toFixed(4)}, ${plan.lonWgs84.toFixed(4)} · ${plan.tzId}）。` +
      '保存将保留原始机位信息；如需更换地点，请先明确选择新机位。';
    return ctx;
  }

  static resolveSave(ctx: EditPlaceContext, selectedIndex: number, places: Place[],
    userChangedPlace: boolean): SavePlaceOutcome {
    const out = new SavePlaceOutcome();
    const picked = selectedIndex >= 0 && selectedIndex < places.length ? places[selectedIndex] : undefined;
    if (userChangedPlace) {
      if (picked === undefined) {
        out.ok = false;
        out.reason = '计划所属地点需要重新选择：当前没有可用的机位。';
        return out;
      }
      out.useSnapshot = false;
      out.effective.placeId = picked.id;
      out.effective.placeName = picked.name;
      out.effective.latWgs84 = picked.latWgs84;
      out.effective.lonWgs84 = picked.lonWgs84;
      out.effective.tzId = picked.tzId;
      out.notice = `计划所属地点已更改为「${picked.name}」，拍摄时刻（UTC）保持不变。`;
      return out;
    }
    if (ctx.detached) {
      out.useSnapshot = true;
      out.effective = ctx.snapshot;
      out.notice = '原机位已删除，已保留计划中的机位快照，未改动地点信息。';
      return out;
    }
    if (picked === undefined) {
      out.ok = false;
      out.reason = '请先选择机位。';
      return out;
    }
    out.useSnapshot = false;
    out.effective.placeId = picked.id;
    out.effective.placeName = picked.name;
    out.effective.latWgs84 = picked.latWgs84;
    out.effective.lonWgs84 = picked.lonWgs84;
    out.effective.tzId = picked.tzId;
    return out;
  }

  /** 把保存结果落到计划对象上：useSnapshot 时**不触碰**任何机位字段 */
  static applyPlace(plan: ShootPlan, outcome: SavePlaceOutcome): void {
    if (!outcome.ok || outcome.useSnapshot) {
      return;
    }
    plan.placeId = outcome.effective.placeId;
    plan.placeName = outcome.effective.placeName;
    plan.latWgs84 = outcome.effective.latWgs84;
    plan.lonWgs84 = outcome.effective.lonWgs84;
    plan.tzId = outcome.effective.tzId;
  }
}
