/**
 * CSV 编码（RFC 4180 转义）。
 *
 * 刻意不依赖任何 @kit 模块：这样本地单元测试（Host 上运行）可以直接覆盖它，
 * 而 ExportService（依赖 picker / fileIo）只负责真正的写文件。
 */
export class CsvCodec {
  private static readonly QUOTE: string = '"';

  /** 单字段转义：含逗号、引号、换行时用双引号包裹并把内部引号翻倍 */
  static escape(cell: string): string {
    const hasComma = cell.includes(',');
    const hasQuote = cell.includes(CsvCodec.QUOTE);
    const hasNewline = cell.includes('\n') || cell.includes('\r');
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
      lines.push(cells.join(','));
    }
    return lines.join('\r\n');
  }

  /** 解析 CSV（用于测试与回读校验；不支持跨行字段以外的复杂引号规则之外的扩展） */
  static parse(text: string): string[][] {
    const rows: string[][] = [];
    const normalized = text.split('\r\n').join('\n');
    const lines: string[] = normalized.split('\n');
    for (const line of lines) {
      if (line.length === 0) {
        continue;
      }
      const cells: string[] = [];
      let current = '';
      let inQuote = false;
      let i = 0;
      while (i < line.length) {
        const ch = line.charAt(i);
        if (inQuote) {
          if (ch === CsvCodec.QUOTE) {
            if (i + 1 < line.length && line.charAt(i + 1) === CsvCodec.QUOTE) {
              current += CsvCodec.QUOTE;
              i += 2;
              continue;
            }
            inQuote = false;
            i++;
            continue;
          }
          current += ch;
          i++;
          continue;
        }
        if (ch === CsvCodec.QUOTE) {
          inQuote = true;
          i++;
          continue;
        }
        if (ch === ',') {
          cells.push(current);
          current = '';
          i++;
          continue;
        }
        current += ch;
        i++;
      }
      cells.push(current);
      rows.push(cells);
    }
    return rows;
  }
}
