import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CsvCodec } from '../utils/CsvCodec';
import { AppDb } from '../repository/AppDb';
import { FileAsset } from '../model/BaseModels';
import { IdGen } from '../model/Models';

const DOMAIN = 0x1004;
const TAG = 'LB_EXPORT';

/** 导出结果：成功时带真实文件 URI，失败带原因 */
export class ExportResult {
  ok: boolean = false;
  /** 实际写入的系统文件 URI（可被文件管理器/外部工具验证） */
  uri: string = '';
  bytes: number = 0;
  message: string = '';
  /** 内容校验和（FNV-1a 32 位，十六进制），写入 FileAsset 供事后核对 */
  checksum: string = '';
  mime: string = '';

  static fail(message: string): ExportResult {
    const r = new ExportResult();
    r.ok = false;
    r.message = message;
    return r;
  }
}

/** 校验和：FNV-1a 32 位，对字节序列稳定可复算（不引入额外依赖） */
export class Checksum {
  static ofBytes(data: ArrayBuffer): string {
    const view = new Uint8Array(data);
    let hash = 0x811c9dc5;
    for (let i = 0; i < view.length; i++) {
      hash = hash ^ view[i];
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return `fnv1a:${hash.toString(16).padStart(8, '0')}`;
  }

  /** UTF-8 编码（与真实写盘字节一致，含代理对/表情符号） */
  static encodeUtf8(text: string): Uint8Array {
    const out: number[] = [];
    for (let i = 0; i < text.length; i++) {
      let cp: number = text.charCodeAt(i);
      if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < text.length) {
        const low: number = text.charCodeAt(i + 1);
        if (low >= 0xDC00 && low <= 0xDFFF) {
          cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
          i++;
        }
      }
      if (cp < 0x80) {
        out.push(cp);
      } else if (cp < 0x800) {
        out.push(0xC0 | (cp >> 6));
        out.push(0x80 | (cp & 0x3F));
      } else if (cp < 0x10000) {
        out.push(0xE0 | (cp >> 12));
        out.push(0x80 | ((cp >> 6) & 0x3F));
        out.push(0x80 | (cp & 0x3F));
      } else {
        out.push(0xF0 | (cp >> 18));
        out.push(0x80 | ((cp >> 12) & 0x3F));
        out.push(0x80 | ((cp >> 6) & 0x3F));
        out.push(0x80 | (cp & 0x3F));
      }
    }
    const bytes = new Uint8Array(out.length);
    for (let i = 0; i < out.length; i++) {
      bytes[i] = out[i];
    }
    return bytes;
  }

  /** 文本校验和：必须与实际写出的 UTF-8 字节一致（不能用 UTF-16 code unit 近似） */
  static ofText(text: string): string {
    const bytes = Checksum.encodeUtf8(text);
    return Checksum.ofBytes(bytes.buffer as ArrayBuffer);
  }
}

/**
 * 文件导出。
 *
 * 使用系统 DocumentViewPicker 由用户选择保存位置，写真实字节；
 * 不使用「分享面板」之外的伪造成功提示：返回的 URI 来自系统，
 * 可由文件管理器独立打开验证。
 */
export class ExportService {
  /** 写 CSV 到用户选择的位置 */
  static async exportCsv(context: common.UIAbilityContext, fileName: string, rows: string[][]): Promise<ExportResult> {
    const content = CsvCodec.build(rows);
    const result = await ExportService.writeText(context, fileName, content);
    if (result.ok) {
      result.mime = 'text/csv';
    }
    return result;
  }

  /** 把导出的文件登记为 FileAsset（设置页可查看与清理记录） */
  static async recordAsset(result: ExportResult, projectId: string): Promise<void> {
    if (!result.ok || result.uri.length === 0) {
      return;
    }
    try {
      const asset = FileAsset.of(IdGen.next('fa'), projectId, result.uri, result.mime,
        result.bytes, result.checksum);
      await AppDb.addFileAsset(asset);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'recordAsset failed: %{public}s', e.message);
    }
  }

  /** 构造真实写出的字节：UTF-8 + BOM（测试与 writeText 共用，避免两套实现漂移） */
  static buildUtf8File(content: string): Uint8Array {
    const body = Checksum.encodeUtf8(content);
    const withBom = new Uint8Array(body.length + 3);
    withBom[0] = 0xEF;
    withBom[1] = 0xBB;
    withBom[2] = 0xBF;
    withBom.set(body, 3);
    return withBom;
  }

  static async writeText(context: common.UIAbilityContext, fileName: string, content: string): Promise<ExportResult> {
    try {
      const options: picker.DocumentSaveOptions = {
        newFileNames: [fileName]
      };
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris = await documentPicker.save(options);
      if (uris.length === 0) {
        return ExportResult.fail('已取消保存');
      }
      const uri = uris[0];
      // UTF-8 + BOM：满足 Excel 对中文 CSV 的识别；校验和基于真实写出字节
      const withBom = ExportService.buildUtf8File(content);
      let written = 0;
      let file: fileIo.File | undefined = undefined;
      try {
        file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        written = fileIo.writeSync(file.fd, withBom.buffer as ArrayBuffer);
      } finally {
        if (file !== undefined) {
          fileIo.closeSync(file);
        }
      }
      if (written !== withBom.length) {
        return ExportResult.fail(`写入不完整：期望 ${withBom.length} 字节，实际 ${written} 字节`);
      }
      const r = new ExportResult();
      r.ok = true;
      r.uri = uri;
      r.bytes = withBom.length;
      r.checksum = Checksum.ofBytes(withBom.buffer as ArrayBuffer);
      return r;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'writeText failed code=%{public}d msg=%{public}s', e.code, e.message);
      return ExportResult.fail(`保存失败：${e.message}（错误码 ${e.code}）`);
    }
  }

  /** 把 PixelMap 编码为 PNG 并保存 */
  static async exportPng(context: common.UIAbilityContext, fileName: string,
    pixelMap: image.PixelMap): Promise<ExportResult> {
    try {
      const packer = image.createImagePacker();
      const option: image.PackingOption = {
        format: 'image/png',
        quality: 100
      };
      const buffer = await packer.packToData(pixelMap, option);
      packer.release();
      const options: picker.DocumentSaveOptions = {
        newFileNames: [fileName]
      };
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris = await documentPicker.save(options);
      if (uris.length === 0) {
        return ExportResult.fail('已取消保存');
      }
      const uri = uris[0];
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const bytes = fileIo.writeSync(file.fd, buffer);
      fileIo.closeSync(file);
      const r = new ExportResult();
      r.ok = true;
      r.uri = uri;
      r.bytes = bytes;
      r.checksum = Checksum.ofBytes(buffer);
      r.mime = 'image/png';
      hilog.info(DOMAIN, TAG, 'png exported bytes=%{public}d', bytes);
      return r;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'exportPng failed code=%{public}d msg=%{public}s', e.code, e.message);
      return ExportResult.fail(`导出图片失败：${e.message}（错误码 ${e.code}）`);
    }
  }
}
