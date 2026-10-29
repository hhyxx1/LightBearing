import { describe, it, expect } from '@ohos/hypium';
import { CsvCodec } from '../main/ets/utils/CsvCodec';

/** CSV 编解码测试（导出文件可被 Excel/外部工具解析的前提） */
export default function csvCodecTest() {
  describe('CsvCodec', () => {
    it('plain_fields_join_with_comma', 0, () => {
      const rows: string[][] = [['a', 'b', 'c'], ['1', '2', '3']];
      expect(CsvCodec.build(rows)).assertEqual('a,b,c\r\n1,2,3');
    });

    it('field_with_comma_is_quoted', 0, () => {
      const rows: string[][] = [['上海, 外滩', '31.2']];
      expect(CsvCodec.build(rows)).assertEqual('"上海, 外滩",31.2');
    });

    it('quotes_are_doubled', 0, () => {
      const rows: string[][] = [['say "hi"', 'x']];
      expect(CsvCodec.build(rows)).assertEqual('"say ""hi""",x');
    });

    it('newline_field_is_quoted', 0, () => {
      const rows: string[][] = [['line1\nline2', 'y']];
      expect(CsvCodec.build(rows)).assertEqual('"line1\nline2",y');
    });

    it('roundtrip_preserves_content', 0, () => {
      const rows: string[][] = [
        ['计划ID', '机位', '备注'],
        ['sp_1', '外滩, 城市天际线', '目标 "250°"'],
        ['sp_2', 'BundViewpoint', '普通']
      ];
      const text = CsvCodec.build(rows);
      const parsed = CsvCodec.parse(text);
      expect(parsed.length).assertEqual(3);
      expect(parsed[1][1]).assertEqual('外滩, 城市天际线');
      expect(parsed[1][2]).assertEqual('目标 "250°"');
      expect(parsed[2][2]).assertEqual('普通');
    });

    it('empty_cell_stays_empty', 0, () => {
      const rows: string[][] = [['a', '', 'c']];
      expect(CsvCodec.build(rows)).assertEqual('a,,c');
    });
  });
}
