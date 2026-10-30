/**
 * 应用数据模型（单一来源，所有页面从这里 import，禁止重复声明）
 *
 * 每个可持久化模型都带 schema 版本语义：字段变更时提升 SchemaVersion 并在
 * AppDb.migrate() 中写显式迁移，不做破坏性重建。
 */

/** 机位（收藏地点） */
export class Place {
  id: string = '';
  name: string = '';
  /** WGS84 纬度，正北 */
  latWgs84: number = 0;
  /** WGS84 经度，东经为正 */
  lonWgs84: number = 0;
  /** IANA 时区 ID */
  tzId: string = 'Asia/Shanghai';
  /** 逗号分隔标签 */
  tags: string = '';
  note: string = '';
  createdAt: number = 0;
  updatedAt: number = 0;

  static of(id: string, name: string, lat: number, lon: number, tzId: string): Place {
    const p = new Place();
    p.id = id;
    p.name = name;
    p.latWgs84 = lat;
    p.lonWgs84 = lon;
    p.tzId = tzId;
    return p;
  }
}

/** 拍摄计划 */
export class ShootPlan {
  id: string = '';
  /** 所属项目（schema v2 起） */
  projectId: string = '';
  placeId: string = '';
  placeName: string = '';
  latWgs84: number = 0;
  lonWgs84: number = 0;
  tzId: string = 'Asia/Shanghai';
  /** 选定时刻（UTC 毫秒） */
  selectedUtc: number = 0;
  targetAzimuth: number = 0;
  targetAltitude: number = 0;
  azTolerance: number = 3;
  altTolerance: number = 3;
  note: string = '';
  /** 天气备忘：用户手写，绝不冒充真实预报 */
  weatherMemo: string = '';
  /** 行前清单，JSON 数组序列化 */
  checklist: string = '[]';
  /** 0=草稿 1=已确认 2=已完成 */
  status: number = 0;
  createdAt: number = 0;
  updatedAt: number = 0;
}

/** 行前清单项 */
export class ChecklistItem {
  id: string = '';
  text: string = '';
  done: boolean = false;

  static of(id: string, text: string, done: boolean): ChecklistItem {
    const c = new ChecklistItem();
    c.id = id;
    c.text = text;
    c.done = done;
    return c;
  }
}

/** 全局设置（键值化存储，字段可扩展） */
export class AppSettings {
  /** 0=跟随系统（默认） 1=深色 2=浅色；深色只表示深色，浅色只表示浅色 */
  themeMode: number = 0;
  /** 0=度 1=弧度 */
  angleUnit: number = 0;
  /** 默认时区，空串表示跟随系统 */
  tzId: string = '';
  /** 0=WGS84（内部唯一存储坐标系） */
  coordSystem: number = 0;
  goldenUpper: number = 6;
  goldenLower: number = -4;
  blueLower: number = -6;
  /** 是否已完成首次引导 */
  onboarded: number = 0;
  /** 默认定位方式：0=手动坐标 1=前台定位 */
  locationMode: number = 0;
  /** 减少动态效果：0=关闭 1=开启（开启后页面切换不播转场动画） */
  reduceMotion: number = 0;
}

/** 历史记录（反向搜索结果、比较结果等） */
export class HistoryRecord {
  id: string = '';
  /** reverse / compare / export / plan */
  kind: string = '';
  summary: string = '';
  /** 序列化负载 */
  payload: string = '';
  createdAt: number = 0;
}

/** 反向搜索结果候选 */
export class Candidate {
  utcMs: number = 0;
  azimuth: number = 0;
  altitude: number = 0;
  azError: number = 0;
  altError: number = 0;
  /** LightPhase 值 */
  phase: number = 0;

  static of(utcMs: number, az: number, alt: number, azErr: number, altErr: number, phase: number): Candidate {
    const c = new Candidate();
    c.utcMs = utcMs;
    c.azimuth = az;
    c.altitude = alt;
    c.azError = azErr;
    c.altError = altErr;
    c.phase = phase;
    return c;
  }
}

/** 反向搜索目标 */
export class SearchGoal {
  placeId: string = '';
  latWgs84: number = 0;
  lonWgs84: number = 0;
  tzId: string = 'Asia/Shanghai';
  /** 目标方位角 */
  azimuthTarget: number = 180;
  /** 目标高度角 */
  altitudeTarget: number = 10;
  azTolerance: number = 3;
  altTolerance: number = 3;
  /** 搜索起始本地日（UTC 毫秒，取当日 00:00） */
  rangeStartUtc: number = 0;
  /** 搜索天数 */
  rangeDays: number = 14;
  /** 过滤：仅保留日出后到日落前（true 时） */
  daylightOnly: boolean = false;
  /** 结果数量上限 */
  maxResults: number = 20;
}

/** 应用启动状态（用于空态/加载/错误） */
export enum LoadState {
  LOADING = 0,
  READY = 1,
  EMPTY = 2,
  ERROR = 3,
  NO_PERMISSION = 4,
  UNSUPPORTED = 5
}

/** 生成轻量唯一 ID */
export class IdGen {
  private static counter: number = 0;

  static next(prefix: string): string {
    IdGen.counter = (IdGen.counter + 1) % 100000;
    const t = new Date().getTime();
    return `${prefix}_${t}_${IdGen.counter}`;
  }
}
