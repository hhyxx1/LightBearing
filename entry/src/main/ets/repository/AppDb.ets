import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Place, ShootPlan, AppSettings, HistoryRecord, IdGen } from '../model/Models';
import { AppProject, FileAsset, Job, JobStatus } from '../model/BaseModels';

const DOMAIN = 0x1001;
const TAG = 'LB_DB';
/** 当前 schema 版本；未来字段变更时 +1 并在 migrate 内补 DDL */
const SCHEMA_VERSION = 2;

/**
 * 本地持久化仓储（ArkData RDB）。
 *
 * 设计要点：
 * - 全部业务表由 _schema 版本驱动迁移，禁止静默重建丢数据；
 * - 写入使用事务，保证「保存计划 + 写历史」原子性；
 * - 坐标恒为 WGS84，时区仅作为展示/输入换算依据。
 */
export class AppDb {
  private static store: relationalStore.RdbStore | undefined = undefined;
  private static initPromise: Promise<void> | undefined = undefined;

  /** 幂等初始化；并发调用共享同一个 Promise */
  static init(context: common.Context): Promise<void> {
    if (AppDb.initPromise !== undefined) {
      return AppDb.initPromise;
    }
    AppDb.initPromise = AppDb.doInit(context);
    return AppDb.initPromise;
  }

  private static async doInit(context: common.Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: 'lightbearing.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);
    AppDb.store = store;
    await AppDb.migrate(store);
    hilog.info(DOMAIN, TAG, 'database ready, schema=%{public}d', SCHEMA_VERSION);
  }

  private static async currentVersion(store: relationalStore.RdbStore): Promise<number> {
    const rs = await store.querySql('PRAGMA user_version');
    let v = 0;
    if (rs.goToFirstRow()) {
      v = rs.getLong(0);
    }
    rs.close();
    return v;
  }

  private static async migrate(store: relationalStore.RdbStore): Promise<void> {
    const from = await AppDb.currentVersion(store);
    if (from >= SCHEMA_VERSION) {
      return;
    }
    store.beginTransaction();
    try {
      if (from < 1) {
        await store.executeSql(`CREATE TABLE IF NOT EXISTS places (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          lat REAL NOT NULL,
          lon REAL NOT NULL,
          tz_id TEXT NOT NULL,
          tags TEXT NOT NULL DEFAULT '',
          note TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL)`);
        await store.executeSql(`CREATE TABLE IF NOT EXISTS plans (
          id TEXT PRIMARY KEY,
          place_id TEXT NOT NULL DEFAULT '',
          place_name TEXT NOT NULL DEFAULT '',
          lat REAL NOT NULL,
          lon REAL NOT NULL,
          tz_id TEXT NOT NULL,
          selected_utc INTEGER NOT NULL,
          target_az REAL NOT NULL DEFAULT 0,
          target_alt REAL NOT NULL DEFAULT 0,
          az_tol REAL NOT NULL DEFAULT 3,
          alt_tol REAL NOT NULL DEFAULT 3,
          note TEXT NOT NULL DEFAULT '',
          weather_memo TEXT NOT NULL DEFAULT '',
          checklist TEXT NOT NULL DEFAULT '[]',
          status INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL)`);
        await store.executeSql(`CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL)`);
        await store.executeSql(`CREATE TABLE IF NOT EXISTS history (
          id TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          summary TEXT NOT NULL,
          payload TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL)`);
        await store.executeSql('CREATE INDEX IF NOT EXISTS idx_plans_selected ON plans(selected_utc)');
        await store.executeSql('CREATE INDEX IF NOT EXISTS idx_history_created ON history(created_at)');
      }
      if (from < 2) {
        // 任务书 §7 基础模型：项目 / 文件资产 / 后台任务
        await store.executeSql(`CREATE TABLE IF NOT EXISTS projects (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          status INTEGER NOT NULL DEFAULT 0,
          schema_version INTEGER NOT NULL DEFAULT 2,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL)`);
        await store.executeSql(`CREATE TABLE IF NOT EXISTS file_assets (
          id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL DEFAULT '',
          sandbox_path TEXT NOT NULL,
          mime TEXT NOT NULL DEFAULT '',
          size INTEGER NOT NULL DEFAULT 0,
          checksum TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL)`);
        await store.executeSql(`CREATE TABLE IF NOT EXISTS jobs (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          status INTEGER NOT NULL DEFAULT 0,
          progress INTEGER NOT NULL DEFAULT 0,
          error_code TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          finished_at INTEGER NOT NULL DEFAULT 0)`);
        await store.executeSql("ALTER TABLE plans ADD COLUMN project_id TEXT NOT NULL DEFAULT ''");
        await store.executeSql('CREATE INDEX IF NOT EXISTS idx_assets_created ON file_assets(created_at)');
        await store.executeSql('CREATE INDEX IF NOT EXISTS idx_jobs_created ON jobs(created_at)');
      }
      await store.executeSql(`PRAGMA user_version = ${SCHEMA_VERSION}`);
      store.commit();
    } catch (err) {
      store.rollBack();
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'migrate failed: %{public}s', JSON.stringify(e));
      throw new Error(`数据库迁移失败：${e.message}`);
    }
  }

  private static requireStore(): relationalStore.RdbStore {
    if (AppDb.store === undefined) {
      throw new Error('数据库尚未初始化');
    }
    return AppDb.store;
  }

  // ---------------- 机位 ----------------

  static async listPlaces(): Promise<Place[]> {
    const store = AppDb.requireStore();
    const rs = await store.querySql('SELECT * FROM places ORDER BY updated_at DESC');
    const list: Place[] = [];
    while (rs.goToNextRow()) {
      list.push(AppDb.readPlace(rs));
    }
    rs.close();
    return list;
  }

  static async searchPlaces(keyword: string): Promise<Place[]> {
    const all = await AppDb.listPlaces();
    if (keyword.length === 0) {
      return all;
    }
    const k = keyword.toLowerCase();
    const out: Place[] = [];
    for (const p of all) {
      if (p.name.toLowerCase().includes(k) || p.tags.toLowerCase().includes(k) || p.note.toLowerCase().includes(k)) {
        out.push(p);
      }
    }
    return out;
  }

  static async getPlace(id: string): Promise<Place | undefined> {
    const store = AppDb.requireStore();
    const rs = await store.querySql('SELECT * FROM places WHERE id = ?', [id]);
    let found: Place | undefined = undefined;
    if (rs.goToNextRow()) {
      found = AppDb.readPlace(rs);
    }
    rs.close();
    return found;
  }

  static async savePlace(p: Place): Promise<void> {
    const store = AppDb.requireStore();
    const now = new Date().getTime();
    const existing = await AppDb.getPlace(p.id);
    if (existing === undefined) {
      p.createdAt = now;
      p.updatedAt = now;
      const values: relationalStore.ValuesBucket = {
        'id': p.id,
        'name': p.name,
        'lat': p.latWgs84,
        'lon': p.lonWgs84,
        'tz_id': p.tzId,
        'tags': p.tags,
        'note': p.note,
        'created_at': p.createdAt,
        'updated_at': p.updatedAt
      };
      await store.insert('places', values);
    } else {
      p.createdAt = existing.createdAt;
      p.updatedAt = now;
      await store.executeSql(
        'UPDATE places SET name = ?, lat = ?, lon = ?, tz_id = ?, tags = ?, note = ?, updated_at = ? WHERE id = ?',
        [p.name, p.latWgs84, p.lonWgs84, p.tzId, p.tags, p.note, p.updatedAt, p.id]
      );
    }
  }

  static async deletePlace(id: string): Promise<void> {
    const store = AppDb.requireStore();
    await store.executeSql('DELETE FROM places WHERE id = ?', [id]);
  }

  private static readPlace(rs: relationalStore.ResultSet): Place {
    const p = new Place();
    p.id = rs.getString(rs.getColumnIndex('id'));
    p.name = rs.getString(rs.getColumnIndex('name'));
    p.latWgs84 = rs.getDouble(rs.getColumnIndex('lat'));
    p.lonWgs84 = rs.getDouble(rs.getColumnIndex('lon'));
    p.tzId = rs.getString(rs.getColumnIndex('tz_id'));
    p.tags = rs.getString(rs.getColumnIndex('tags'));
    p.note = rs.getString(rs.getColumnIndex('note'));
    p.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    p.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    return p;
  }

  // ---------------- 拍摄计划 ----------------

  static async listPlans(): Promise<ShootPlan[]> {
    const store = AppDb.requireStore();
    const rs = await store.querySql('SELECT * FROM plans ORDER BY selected_utc ASC');
    const list: ShootPlan[] = [];
    while (rs.goToNextRow()) {
      list.push(AppDb.readPlan(rs));
    }
    rs.close();
    return list;
  }

  static async getPlan(id: string): Promise<ShootPlan | undefined> {
    const store = AppDb.requireStore();
    const rs = await store.querySql('SELECT * FROM plans WHERE id = ?', [id]);
    let found: ShootPlan | undefined = undefined;
    if (rs.goToNextRow()) {
      found = AppDb.readPlan(rs);
    }
    rs.close();
    return found;
  }

  /** 保存计划并在同一事务内追加历史记录 */
  static async savePlan(plan: ShootPlan, historySummary: string): Promise<void> {
    const store = AppDb.requireStore();
    const now = new Date().getTime();
    const existing = await AppDb.getPlan(plan.id);
    store.beginTransaction();
    try {
      if (existing === undefined) {
        plan.createdAt = now;
        plan.updatedAt = now;
        const values: relationalStore.ValuesBucket = {
          'id': plan.id,
          'project_id': plan.projectId,
          'place_id': plan.placeId,
          'place_name': plan.placeName,
          'lat': plan.latWgs84,
          'lon': plan.lonWgs84,
          'tz_id': plan.tzId,
          'selected_utc': plan.selectedUtc,
          'target_az': plan.targetAzimuth,
          'target_alt': plan.targetAltitude,
          'az_tol': plan.azTolerance,
          'alt_tol': plan.altTolerance,
          'note': plan.note,
          'weather_memo': plan.weatherMemo,
          'checklist': plan.checklist,
          'status': plan.status,
          'created_at': plan.createdAt,
          'updated_at': plan.updatedAt
        };
        await store.insert('plans', values);
      } else {
        plan.createdAt = existing.createdAt;
        plan.updatedAt = now;
        await store.executeSql(
          `UPDATE plans SET project_id = ?, place_id = ?, place_name = ?, lat = ?, lon = ?, tz_id = ?, selected_utc = ?,
           target_az = ?, target_alt = ?, az_tol = ?, alt_tol = ?, note = ?, weather_memo = ?,
           checklist = ?, status = ?, updated_at = ? WHERE id = ?`,
          [plan.projectId, plan.placeId, plan.placeName, plan.latWgs84, plan.lonWgs84, plan.tzId, plan.selectedUtc,
            plan.targetAzimuth, plan.targetAltitude, plan.azTolerance, plan.altTolerance, plan.note,
            plan.weatherMemo, plan.checklist, plan.status, plan.updatedAt, plan.id]
        );
      }
      await AppDb.writeHistory(store, 'plan', historySummary, '');
      store.commit();
    } catch (err) {
      store.rollBack();
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'savePlan failed: %{public}s', JSON.stringify(e));
      throw new Error(`保存计划失败：${e.message}`);
    }
  }

  static async deletePlan(id: string): Promise<void> {
    const store = AppDb.requireStore();
    await store.executeSql('DELETE FROM plans WHERE id = ?', [id]);
  }

  private static readPlan(rs: relationalStore.ResultSet): ShootPlan {
    const p = new ShootPlan();
    p.id = rs.getString(rs.getColumnIndex('id'));
    p.projectId = rs.getString(rs.getColumnIndex('project_id'));
    p.placeId = rs.getString(rs.getColumnIndex('place_id'));
    p.placeName = rs.getString(rs.getColumnIndex('place_name'));
    p.latWgs84 = rs.getDouble(rs.getColumnIndex('lat'));
    p.lonWgs84 = rs.getDouble(rs.getColumnIndex('lon'));
    p.tzId = rs.getString(rs.getColumnIndex('tz_id'));
    p.selectedUtc = rs.getLong(rs.getColumnIndex('selected_utc'));
    p.targetAzimuth = rs.getDouble(rs.getColumnIndex('target_az'));
    p.targetAltitude = rs.getDouble(rs.getColumnIndex('target_alt'));
    p.azTolerance = rs.getDouble(rs.getColumnIndex('az_tol'));
    p.altTolerance = rs.getDouble(rs.getColumnIndex('alt_tol'));
    p.note = rs.getString(rs.getColumnIndex('note'));
    p.weatherMemo = rs.getString(rs.getColumnIndex('weather_memo'));
    p.checklist = rs.getString(rs.getColumnIndex('checklist'));
    p.status = rs.getLong(rs.getColumnIndex('status'));
    p.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    p.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    return p;
  }

  // ---------------- 设置 ----------------

  static async loadSettings(): Promise<AppSettings> {
    const store = AppDb.requireStore();
    const s = new AppSettings();
    const rs = await store.querySql('SELECT key, value FROM settings');
    while (rs.goToNextRow()) {
      const key = rs.getString(0);
      const raw = rs.getString(1);
      if (key === 'themeMode') {
        s.themeMode = Number.parseInt(raw);
      } else if (key === 'angleUnit') {
        s.angleUnit = Number.parseInt(raw);
      } else if (key === 'tzId') {
        s.tzId = raw;
      } else if (key === 'coordSystem') {
        s.coordSystem = Number.parseInt(raw);
      } else if (key === 'goldenUpper') {
        s.goldenUpper = Number.parseFloat(raw);
      } else if (key === 'goldenLower') {
        s.goldenLower = Number.parseFloat(raw);
      } else if (key === 'blueLower') {
        s.blueLower = Number.parseFloat(raw);
      } else if (key === 'onboarded') {
        s.onboarded = Number.parseInt(raw);
      } else if (key === 'locationMode') {
        s.locationMode = Number.parseInt(raw);
      } else if (key === 'reduceMotion') {
        s.reduceMotion = Number.parseInt(raw);
      }
    }
    rs.close();
    return s;
  }

  static async saveSettings(s: AppSettings): Promise<void> {
    const store = AppDb.requireStore();
    const pairs: string[][] = [
      ['themeMode', `${s.themeMode}`],
      ['angleUnit', `${s.angleUnit}`],
      ['tzId', s.tzId],
      ['coordSystem', `${s.coordSystem}`],
      ['goldenUpper', `${s.goldenUpper}`],
      ['goldenLower', `${s.goldenLower}`],
      ['blueLower', `${s.blueLower}`],
      ['onboarded', `${s.onboarded}`],
      ['locationMode', `${s.locationMode}`],
      ['reduceMotion', `${s.reduceMotion}`]
    ];
    store.beginTransaction();
    try {
      for (const pair of pairs) {
        await store.executeSql('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [pair[0], pair[1]]);
      }
      store.commit();
    } catch (err) {
      store.rollBack();
      const e = err as BusinessError;
      throw new Error(`保存设置失败：${e.message}`);
    }
  }

  // ---------------- 历史 ----------------

  static async listHistory(limit: number): Promise<HistoryRecord[]> {
    const store = AppDb.requireStore();
    const rs = await store.querySql('SELECT * FROM history ORDER BY created_at DESC LIMIT ?', [limit]);
    const list: HistoryRecord[] = [];
    while (rs.goToNextRow()) {
      const h = new HistoryRecord();
      h.id = rs.getString(rs.getColumnIndex('id'));
      h.kind = rs.getString(rs.getColumnIndex('kind'));
      h.summary = rs.getString(rs.getColumnIndex('summary'));
      h.payload = rs.getString(rs.getColumnIndex('payload'));
      h.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
      list.push(h);
    }
    rs.close();
    return list;
  }

  static async addHistory(kind: string, summary: string, payload: string): Promise<void> {
    const store = AppDb.requireStore();
    await AppDb.writeHistory(store, kind, summary, payload);
  }

  private static async writeHistory(store: relationalStore.RdbStore, kind: string, summary: string,
    payload: string): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'id': IdGen.next('h'),
      'kind': kind,
      'summary': summary,
      'payload': payload,
      'created_at': new Date().getTime()
    };
    await store.insert('history', values);
  }

  static async clearHistory(): Promise<void> {
    const store = AppDb.requireStore();
    await store.executeSql('DELETE FROM history');
  }

  /** 只写一个键，避免把内存里的默认值整体落库（例如引导完成时不应固化 themeMode） */
  static async saveSetting(key: string, value: string): Promise<void> {
    const store = AppDb.requireStore();
    await store.executeSql('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, value]);
  }

  // ---------------- 项目 / 文件资产 / 后台任务（schema v2） ----------------

  static async listProjects(): Promise<AppProject[]> {
    const store = AppDb.requireStore();
    const rs = await store.querySql('SELECT * FROM projects ORDER BY created_at ASC');
    const list: AppProject[] = [];
    while (rs.goToNextRow()) {
      const p = new AppProject();
      p.id = rs.getString(rs.getColumnIndex('id'));
      p.name = rs.getString(rs.getColumnIndex('name'));
      p.status = rs.getLong(rs.getColumnIndex('status'));
      p.schemaVersion = rs.getLong(rs.getColumnIndex('schema_version'));
      p.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
      p.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
      list.push(p);
    }
    rs.close();
    return list;
  }

  /** 保证至少有一个项目可用；首个自动命名为「默认项目」 */
  static async ensureDefaultProject(): Promise<AppProject> {
    const existing = await AppDb.listProjects();
    if (existing.length > 0) {
      return existing[0];
    }
    const project = AppProject.of(IdGen.next('prj'), '默认项目');
    await AppDb.saveProject(project);
    return project;
  }

  static async saveProject(project: AppProject): Promise<void> {
    const store = AppDb.requireStore();
    const now = new Date().getTime();
    const rs = await store.querySql('SELECT id, created_at FROM projects WHERE id = ?', [project.id]);
    let exists = false;
    let createdAt = now;
    if (rs.goToNextRow()) {
      exists = true;
      createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    }
    rs.close();
    if (exists) {
      project.createdAt = createdAt;
      project.updatedAt = now;
      await store.executeSql('UPDATE projects SET name = ?, status = ?, schema_version = ?, updated_at = ? WHERE id = ?',
        [project.name, project.status, project.schemaVersion, project.updatedAt, project.id]);
      return;
    }
    project.createdAt = now;
    project.updatedAt = now;
    const values: relationalStore.ValuesBucket = {
      'id': project.id,
      'name': project.name,
      'status': project.status,
      'schema_version': project.schemaVersion,
      'created_at': project.createdAt,
      'updated_at': project.updatedAt
    };
    await store.insert('projects', values);
  }

  /** 删除项目：计划不被删除，只解除项目归属；同时清理该项目的文件资产记录 */
  static async deleteProject(id: string): Promise<void> {
    const store = AppDb.requireStore();
    store.beginTransaction();
    try {
      await store.executeSql("UPDATE plans SET project_id = '' WHERE project_id = ?", [id]);
      await store.executeSql('DELETE FROM file_assets WHERE project_id = ?', [id]);
      await store.executeSql('DELETE FROM projects WHERE id = ?', [id]);
      store.commit();
    } catch (err) {
      store.rollBack();
      throw new Error(`删除项目失败：${(err as BusinessError).message}`);
    }
  }

  static async listFileAssets(limit: number): Promise<FileAsset[]> {
    const store = AppDb.requireStore();
    const rs = await store.querySql('SELECT * FROM file_assets ORDER BY created_at DESC LIMIT ?', [limit]);
    const list: FileAsset[] = [];
    while (rs.goToNextRow()) {
      const a = new FileAsset();
      a.id = rs.getString(rs.getColumnIndex('id'));
      a.projectId = rs.getString(rs.getColumnIndex('project_id'));
      a.sandboxPath = rs.getString(rs.getColumnIndex('sandbox_path'));
      a.mime = rs.getString(rs.getColumnIndex('mime'));
      a.size = rs.getLong(rs.getColumnIndex('size'));
      a.checksum = rs.getString(rs.getColumnIndex('checksum'));
      a.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
      list.push(a);
    }
    rs.close();
    return list;
  }

  static async addFileAsset(asset: FileAsset): Promise<void> {
    const store = AppDb.requireStore();
    asset.createdAt = new Date().getTime();
    const values: relationalStore.ValuesBucket = {
      'id': asset.id,
      'project_id': asset.projectId,
      'sandbox_path': asset.sandboxPath,
      'mime': asset.mime,
      'size': asset.size,
      'checksum': asset.checksum,
      'created_at': asset.createdAt
    };
    await store.insert('file_assets', values);
  }

  /** 仅清理记录，不删除用户已保存的文件（文件在用户选择的位置） */
  static async clearFileAssets(): Promise<void> {
    const store = AppDb.requireStore();
    await store.executeSql('DELETE FROM file_assets');
  }

  /** [条数, 总字节数] */
  static async assetTotals(): Promise<number[]> {
    const store = AppDb.requireStore();
    const rs = await store.querySql('SELECT COUNT(*) AS c, COALESCE(SUM(size), 0) AS s FROM file_assets');
    let count = 0;
    let size = 0;
    if (rs.goToFirstRow()) {
      count = rs.getLong(0);
      size = rs.getLong(1);
    }
    rs.close();
    return [count, size];
  }

  static async createJob(job: Job): Promise<void> {
    const store = AppDb.requireStore();
    job.createdAt = new Date().getTime();
    const values: relationalStore.ValuesBucket = {
      'id': job.id,
      'type': job.type,
      'status': job.status,
      'progress': job.progress,
      'error_code': job.errorCode,
      'created_at': job.createdAt,
      'finished_at': job.finishedAt
    };
    await store.insert('jobs', values);
  }

  static async updateJob(id: string, status: number, progress: number, errorCode: string): Promise<void> {
    const store = AppDb.requireStore();
    const finishedAt = status === JobStatus.RUNNING || status === JobStatus.QUEUED ? 0 : new Date().getTime();
    await store.executeSql('UPDATE jobs SET status = ?, progress = ?, error_code = ?, finished_at = ? WHERE id = ?',
      [status, progress, errorCode, finishedAt, id]);
  }

  static async listRecentJobs(limit: number): Promise<Job[]> {
    const store = AppDb.requireStore();
    const rs = await store.querySql('SELECT * FROM jobs ORDER BY created_at DESC LIMIT ?', [limit]);
    const list: Job[] = [];
    while (rs.goToNextRow()) {
      const j = new Job();
      j.id = rs.getString(rs.getColumnIndex('id'));
      j.type = rs.getString(rs.getColumnIndex('type'));
      j.status = rs.getLong(rs.getColumnIndex('status'));
      j.progress = rs.getLong(rs.getColumnIndex('progress'));
      j.errorCode = rs.getString(rs.getColumnIndex('error_code'));
      j.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
      j.finishedAt = rs.getLong(rs.getColumnIndex('finished_at'));
      list.push(j);
    }
    rs.close();
    return list;
  }

  static async clearFinishedJobs(): Promise<void> {
    const store = AppDb.requireStore();
    await store.executeSql('DELETE FROM jobs WHERE status IN (?, ?, ?)',
      [JobStatus.DONE, JobStatus.FAILED, JobStatus.CANCELLED]);
  }

  /** 数据库统计（设置页展示真实体积） */
  static async stats(): Promise<number[]> {
    const places = await AppDb.countOf('places');
    const plans = await AppDb.countOf('plans');
    const history = await AppDb.countOf('history');
    return [places, plans, history];
  }

  private static async countOf(table: string): Promise<number> {
    const store = AppDb.requireStore();
    const rs = await store.querySql(`SELECT COUNT(*) AS c FROM ${table}`);
    let c = 0;
    if (rs.goToFirstRow()) {
      c = rs.getLong(0);
    }
    rs.close();
    return c;
  }
}
