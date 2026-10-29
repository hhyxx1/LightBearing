import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppDb } from '../repository/AppDb';
import { AppSettings, Place, ShootPlan, IdGen } from '../model/Models';
import { LightThresholds } from '../services/SolarCalc';
import { TimeUtil } from '../services/TimeUtil';
import { Theme } from './Theme';

const DOMAIN = 0x1006;
const TAG = 'LB_STATE';

/**
 * 跨页面共享的业务状态。
 *
 * 不缓存「演示数据」：所有字段都来自 AppDb 的真实读写；
 * bootstrap() 在 EntryAbility 与页面 aboutToAppear 中均可安全调用（幂等）。
 */
export class AppState {
  static settings: AppSettings = new AppSettings();
  static places: Place[] = [];
  static plans: ShootPlan[] = [];
  /** 当前工作机位；为空时页面必须走空态引导 */
  static currentPlace: Place | undefined = undefined;
  static ready: boolean = false;
  /** 上次错误（用于错误态展示与重试） */
  static lastError: string = '';

  static async bootstrap(context: common.Context): Promise<void> {
    if (AppState.ready) {
      return;
    }
    try {
      await AppDb.init(context);
      AppState.settings = await AppDb.loadSettings();
      await AppState.reloadData();
      Theme.apply(context, AppState.settings.themeMode);
      AppState.ready = true;
      AppState.lastError = '';
      hilog.info(DOMAIN, TAG, 'bootstrap ok places=%{public}d plans=%{public}d',
        AppState.places.length, AppState.plans.length);
    } catch (err) {
      AppState.ready = false;
      AppState.lastError = `初始化失败：${(err as Error).message}`;
      hilog.error(DOMAIN, TAG, 'bootstrap failed %{public}s', AppState.lastError);
      throw err as Error;
    }
  }

  static async reloadData(): Promise<void> {
    AppState.places = await AppDb.listPlaces();
    AppState.plans = await AppDb.listPlans();
    if (AppState.currentPlace !== undefined) {
      const id = AppState.currentPlace.id;
      let found: Place | undefined = undefined;
      for (const p of AppState.places) {
        if (p.id === id) {
          found = p;
        }
      }
      AppState.currentPlace = found;
    }
    if (AppState.currentPlace === undefined && AppState.places.length > 0) {
      AppState.currentPlace = AppState.places[0];
    }
  }

  /** 生效时区：优先机位时区，其次设置，最后系统 */
  static effectiveTzId(): string {
    if (AppState.currentPlace !== undefined) {
      return AppState.currentPlace.tzId;
    }
    if (AppState.settings.tzId.length > 0) {
      return AppState.settings.tzId;
    }
    return TimeUtil.deviceTimeZoneId();
  }

  static thresholds(): LightThresholds {
    const th = new LightThresholds();
    th.goldenUpperDeg = AppState.settings.goldenUpper;
    th.goldenLowerDeg = AppState.settings.goldenLower;
    th.blueLowerDeg = AppState.settings.blueLower;
    return th;
  }

  /** 保存设置并立即应用 */
  static async persistSettings(context: common.Context): Promise<void> {
    await AppDb.saveSettings(AppState.settings);
    Theme.apply(context, AppState.settings.themeMode);
  }

  /** 新增或更新机位，并把当前工作机位切到它 */
  static async savePlace(place: Place): Promise<void> {
    await AppDb.savePlace(place);
    await AppState.reloadData();
    AppState.currentPlace = place;
  }

  static async deletePlace(id: string): Promise<void> {
    await AppDb.deletePlace(id);
    if (AppState.currentPlace !== undefined && AppState.currentPlace.id === id) {
      AppState.currentPlace = undefined;
    }
    await AppState.reloadData();
  }

  static setCurrentPlace(place: Place): void {
    AppState.currentPlace = place;
  }

  /** 用坐标快速建机位（定位结果、地图点选都走这里） */
  static buildPlace(name: string, lat: number, lon: number, tzId: string, tags: string): Place {
    return Place.of(IdGen.next('p'), name, lat, lon, tzId);
  }

  static findPlace(id: string): Place | undefined {
    for (const p of AppState.places) {
      if (p.id === id) {
        return p;
      }
    }
    return undefined;
  }

  static plansForPlace(placeId: string): ShootPlan[] {
    const list: ShootPlan[] = [];
    for (const plan of AppState.plans) {
      if (plan.placeId === placeId) {
        list.push(plan);
      }
    }
    return list;
  }
}
