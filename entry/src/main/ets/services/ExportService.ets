import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CsvCodec } from '../utils/CsvCodec';

const DOMAIN = 0x1004;
const TAG = 'LB_EXPORT';

/** 导出结果：成功时带真实文件 URI，失败带原因 */
export class ExportResult {
  ok: boolean = false;
  /** 实际写入的系统文件 URI（可被文件管理器/外部工具验证） */
  uri: string = '';
  bytes: number = 0;
  message: string = '';

  static fail(message: string): ExportResult {
    const r = new ExportResult();
    r.ok = false;
    r.message = message;
    return r;
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
    return ExportService.writeText(context, fileName, content);
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
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const bytes = fileIo.writeSync(file.fd, content);
      fileIo.closeSync(file);
      const r = new ExportResult();
      r.ok = true;
      r.uri = uri;
      r.bytes = bytes;
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
      hilog.info(DOMAIN, TAG, 'png exported bytes=%{public}d', bytes);
      return r;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'exportPng failed code=%{public}d msg=%{public}s', e.code, e.message);
      return ExportResult.fail(`导出图片失败：${e.message}（错误码 ${e.code}）`);
    }
  }
}
