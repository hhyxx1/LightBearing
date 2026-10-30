/**
 * 任务书 §7 要求的基础模型：AppProject / FileAsset / Job。
 *
 * 与 plan/place 一样：字段变更时提升 schema 版本并在 AppDb.migrate() 里写显式迁移，
 * 不做破坏性重建。
 */

/** 项目：计划与导出文件的容器（首个项目自动创建为「默认项目」） */
export class AppProject {
  id: string = '';
  name: string = '';
  /** 0=进行中 1=已归档 */
  status: number = 0;
  /** 该记录写入时的 schema 版本，便于逐条迁移 */
  schemaVersion: number = 2;
  createdAt: number = 0;
  updatedAt: number = 0;

  static of(id: string, name: string): AppProject {
    const p = new AppProject();
    p.id = id;
    p.name = name;
    return p;
  }
}

/** 导出/落盘文件资产：记录真实写出的文件，便于校验与清理 */
export class FileAsset {
  id: string = '';
  projectId: string = '';
  /** 系统签发的 URI（不依赖会失效的临时 Picker URI） */
  sandboxPath: string = '';
  mime: string = '';
  size: number = 0;
  /** 内容校验和（SHA256 前 16 位十六进制） */
  checksum: string = '';
  createdAt: number = 0;

  static of(id: string, projectId: string, uri: string, mime: string, size: number,
    checksum: string): FileAsset {
    const a = new FileAsset();
    a.id = id;
    a.projectId = projectId;
    a.sandboxPath = uri;
    a.mime = mime;
    a.size = size;
    a.checksum = checksum;
    return a;
  }
}

/** 后台任务：长耗时计算（如跨月反向搜索）的状态与进度 */
export class Job {
  id: string = '';
  /** reverse / export / compare */
  type: string = '';
  /** 0=排队 1=运行 2=完成 3=失败 4=取消 */
  status: number = 0;
  /** 0-100 */
  progress: number = 0;
  errorCode: string = '';
  createdAt: number = 0;
  finishedAt: number = 0;

  static of(id: string, type: string): Job {
    const j = new Job();
    j.id = id;
    j.type = type;
    j.status = 0;
    j.progress = 0;
    return j;
  }
}

/** Job 状态常量（避免散落魔法数字） */
export class JobStatus {
  static readonly QUEUED: number = 0;
  static readonly RUNNING: number = 1;
  static readonly DONE: number = 2;
  static readonly FAILED: number = 3;
  static readonly CANCELLED: number = 4;
}
