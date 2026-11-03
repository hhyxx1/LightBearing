import { describe, it, expect } from '@ohos/hypium';
import { Checksum, ExportService } from '../main/ets/services/ExportService';
import { CsvCodec } from '../main/ets/utils/CsvCodec';

/**
 * QA-2B / QA-05：CSV 导出的字节级验证。
 * 断言真实 UTF-8 字节、BOM、字节数与校验和一致，并用独立的 FNV-1a（BigInt 实现）交叉验证。
 */

/** 独立实现的 FNV-1a（BigInt，显式 32 位取模，避免与生产实现共用同一段代码） */
function fnv1aBigInt(bytes: Uint8Array): string {
  let h: bigint = BigInt('0x811c9dc5');
  const prime: bigint = BigInt(16777619);
  const mod: bigint = BigInt(4294967296);
  for (let i = 0; i < bytes.length; i++) {
    h = h ^ BigInt(bytes[i]);
    h = (h * prime) % mod;
  }
  return `fnv1a:${h.toString(16).padStart(8, '0')}`;
}

export default function exportBytesTest() {
  describe('ExportBytes', () => {
    it('utf8_bytes_for_chinese_and_emoji', 0, () => {
      const bytes = Checksum.encodeUtf8('中文🙂');
      // 中 E4B8AD 文 E69687 🙂 F09F9982 → 10 字节
      expect(bytes.length).assertEqual(10);
      expect(bytes[0]).assertEqual(0xE4);
      expect(bytes[1]).assertEqual(0xB8);
      expect(bytes[2]).assertEqual(0xAD);
      expect(bytes[3]).assertEqual(0xE6);
      expect(bytes[4]).assertEqual(0x96);
      expect(bytes[5]).assertEqual(0x87);
      expect(bytes[6]).assertEqual(0xF0);
      expect(bytes[7]).assertEqual(0x9F);
      expect(bytes[8]).assertEqual(0x99);
      expect(bytes[9]).assertEqual(0x82);
    });

    it('csv_file_starts_with_utf8_bom_and_keeps_real_bytes', 0, () => {
      const file = ExportService.buildUtf8File('日期,事件\r\n2026-11-03,日落\r\n');
      expect(file[0]).assertEqual(0xEF);
      expect(file[1]).assertEqual(0xBB);
      expect(file[2]).assertEqual(0xBF);
      const body = Checksum.encodeUtf8('日期,事件\r\n2026-11-03,日落\r\n');
      expect(file.length).assertEqual(body.length + 3);
      // BOM 之后的字节必须与正文 UTF-8 完全一致
      for (let i = 0; i < body.length; i++) {
        expect(file[i + 3]).assertEqual(body[i]);
      }
    });

    it('checksum_of_text_equals_checksum_of_utf8_bytes', 0, () => {
      const text = '标题,副标题\r\n中文,"带引号""的值"\r\n🙂,x';
      const bytes = Checksum.encodeUtf8(text);
      expect(Checksum.ofText(text)).assertEqual(Checksum.ofBytes(bytes.buffer as ArrayBuffer));
    });

    it('checksum_matches_independent_fnv1a_implementation', 0, () => {
      const text = '目标方位,目标高度\r\n180.0,10.0\r\n中文备注,"a,b"\r\n🙂🙃,ok';
      const bytes = Checksum.encodeUtf8(text);
      expect(Checksum.ofText(text)).assertEqual(fnv1aBigInt(bytes));
      // 含 BOM 的文件字节校验和也要能被独立实现复现
      const file = ExportService.buildUtf8File(text);
      expect(Checksum.ofBytes(file.buffer as ArrayBuffer)).assertEqual(fnv1aBigInt(file));
    });

    it('checksum_is_byte_based_not_char_length', 0, () => {
      // 同一字符数、不同字节数（中文 vs ASCII）必须得到不同校验和
      const zh = '中中中中';
      const ascii = 'abcd';
      expect(zh.length).assertEqual(ascii.length);
      expect(Checksum.ofText(zh) === Checksum.ofText(ascii)).assertFalse();
      expect(Checksum.encodeUtf8(zh).length).assertEqual(12);
      expect(Checksum.encodeUtf8(ascii).length).assertEqual(4);
    });

    it('csv_parse_strips_bom_from_first_cell', 0, () => {
      const rows = CsvCodec.parse('\uFEFF日期,事件\r\n2026-11-03,日落');
      expect(rows.length).assertEqual(2);
      expect(rows[0][0]).assertEqual('日期');
      expect(rows[0][1]).assertEqual('事件');
      expect(rows[1][0]).assertEqual('2026-11-03');
    });

    it('csv_roundtrip_keeps_commas_and_quotes', 0, () => {
      const rows: string[][] = [['日期', '备注'], ['2026-11-03', 'a,b "c"']];
      const text = CsvCodec.build(rows);
      const back = CsvCodec.parse(text);
      expect(back.length).assertEqual(2);
      expect(back[0][1]).assertEqual('备注');
      expect(back[1][1]).assertEqual('a,b "c"');
      // 导出后再解析（含 BOM 的真实文件文本）
      const withBom = `\uFEFF${text}`;
      const back2 = CsvCodec.parse(withBom);
      expect(back2[0][0]).assertEqual('日期');
    });

    it('csv_multiline_quoted_field_roundtrip', 0, () => {
      // 引号内的换行属于同一字段，不能被拆成多条记录
      const rows: string[][] = [['机位', '备注'], ['上海', '第一天拍摄\n第二天继续']];
      const text = CsvCodec.build(rows);
      const back = CsvCodec.parse(text);
      expect(back.length).assertEqual(2);
      expect(back[1][1]).assertEqual('第一天拍摄\n第二天继续');
    });

    it('csv_parses_lf_crlf_and_bom', 0, () => {
      const lfRows = CsvCodec.parse('a,b\nc,d');
      expect(lfRows.length).assertEqual(2);
      expect(lfRows[0][0]).assertEqual('a');
      const crlfRows = CsvCodec.parse('a,b\r\nc,d\r\n');
      expect(crlfRows.length).assertEqual(2);
      expect(crlfRows[1][1]).assertEqual('d');
      const bomRows = CsvCodec.parse('\uFEFF日期,事件\r\n2026-11-03,日落');
      expect(bomRows[0][0]).assertEqual('日期');
    });

    it('csv_keeps_empty_fields_and_quotes', 0, () => {
      const rows: string[][] = [['a', '', 'c'], ['"quoted"', 'x,y', '']];
      const back = CsvCodec.parse(CsvCodec.build(rows));
      expect(back[0][1]).assertEqual('');
      expect(back[1][0]).assertEqual('"quoted"');
      expect(back[1][1]).assertEqual('x,y');
      expect(back[1][2]).assertEqual('');
    });

    it('utf8_replaces_lone_surrogates_with_fffd', 0, () => {
      const lone = 'a' + String.fromCharCode(0xD800) + 'b';
      const bytes = Checksum.encodeUtf8(lone);
      expect(bytes.length).assertEqual(5);
      expect(bytes[1]).assertEqual(0xEF);
      expect(bytes[2]).assertEqual(0xBF);
      expect(bytes[3]).assertEqual(0xBD);
      const ok = Checksum.encodeUtf8('🙂');
      expect(ok.length).assertEqual(4);
      expect(ok[0]).assertEqual(0xF0);
    });
  });
}
