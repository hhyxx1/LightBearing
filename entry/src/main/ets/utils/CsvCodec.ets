/**
 * CSV 编码（RFC 4180 转义）。
 *
 * 刻意不依赖任何 @kit 模块：这样本地单元测试（Host 上运行）可以直接覆盖它，
 * 而 ExportService（依赖 picker / fileIo）只负责真正的写文件。
 */
export class CsvCodec {
  private static readonly QUOTE: string = '"';
  private static readonly COMMA: string = ',';
  private static readonly CR: string = '\r';
  private static readonly LF: string = '\n';
  private static readonly BOM: number = 0xFEFF;

  /** 单字段转义：含逗号、引号、换行时用双引号包裹并把内部引号翻倍 */
  static escape(cell: string): string {
    const hasComma = cell.includes(CsvCodec.COMMA);
    const hasQuote = cell.includes(CsvCodec.QUOTE);
    const hasNewline = cell.includes(CsvCodec.LF) || cell.includes(CsvCodec.CR);
    if (hasComma || hasQuote || hasNewline) {
      const doubled = cell.split(CsvCodec.QUOTE).join(`${CsvCodec.QUOTE}${CsvCodec.QUOTE}`);
      return `${CsvCodec.QUOTE}${doubled}${CsvCodec.QUOTE}`;
    }
    return cell;
  }

  /** 行集合 → CSV 文本（CRLF 换行） */
  static build(rows: string[][]): string {
    const lines: string[] = [];
    for (const row of rows) {
      const cells: string[] = [];
      for (const cell of row) {
        cells.push(CsvCodec.escape(cell));
      }
      lines.push(cells.join(CsvCodec.COMMA));
    }
    return lines.join('\r\n');
  }

  /**
   * 解析 CSV：整篇状态机，**支持引号内的换行**（跨行字段不会被拆成多条记录）、
   * CRLF 与 LF 两种行尾、双引号转义、空字段，以及开头的 UTF-8 BOM。
   */
  static parse(text: string): string[][] {
    const rows: string[][] = [];
    const src: string = text.charCodeAt(0) === CsvCodec.BOM ? text.substring(1) : text;
    let row: string[] = [];
    let cell: string = '';
    let inQuote: boolean = false;
    let i: number = 0;
    while (i < src.length) {
      const ch: string = src.charAt(i);
      if (inQuote) {
        if (ch === CsvCodec.QUOTE) {
          if (i + 1 < src.length && src.charAt(i + 1) === CsvCodec.QUOTE) {
            cell += CsvCodec.QUOTE;
            i += 2;
            continue;
          }
          inQuote = false;
          i++;
          continue;
        }
        // 引号内的换行属于字段内容
        cell += ch;
        i++;
        continue;
      }
      if (ch === CsvCodec.QUOTE) {
        inQuote = true;
        i++;
        continue;
      }
      if (ch === CsvCodec.COMMA) {
        row.push(cell);
        cell = '';
        i++;
        continue;
      }
      if (ch === CsvCodec.CR) {
        // CRLF 与孤立 CR 都视为行结束
        if (i + 1 < src.length && src.charAt(i + 1) === CsvCodec.LF) {
          i++;
        }
        row.push(cell);
        rows.push(row);
        row = [];
        cell = '';
        i++;
        continue;
      }
      if (ch === CsvCodec.LF) {
        row.push(cell);
        rows.push(row);
        row = [];
        cell = '';
        i++;
        continue;
      }
      cell += ch;
      i++;
    }
    if (cell.length > 0 || row.length > 0) {
      row.push(cell);
      rows.push(row);
    }
    return rows;
  }
}
