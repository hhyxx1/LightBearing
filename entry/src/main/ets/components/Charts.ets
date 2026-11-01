import { common } from '@kit.AbilityKit';
import { ThemeColors, FontSize } from '../common/Theme';
import { SolarCalc, SunPosition, LightThresholds } from '../services/SolarCalc';
import { TimeUtil } from '../services/TimeUtil';
import { Timeline, TimelineModel } from '../services/Timeline';
import { TimelineLabels, TimelineTick } from '../services/TimelineLabels';

/** 采样点 */
class Sample {
  utcMs: number = 0;
  altitude: number = 0;
  azimuth: number = 0;
}

/**
 * 按真实本地日区间采样：[startUtc, endUtc)，步长 10/15 分钟。
 * 不再使用 dayStart + 86400000 —— 夏令时切换日可能是 23/25/23.5/24.5 小时。
 */
function sampleRange(startUtc: number, endUtc: number, lat: number, lon: number, stepMinutes: number): Sample[] {
  const out: Sample[] = [];
  const model: TimelineModel = Timeline.fromBounds(startUtc, endUtc);
  if (!model.valid) {
    return out;
  }
  const times: number[] = Timeline.sampleTimes(model, stepMinutes * 60000);
  for (const t of times) {
    const pos: SunPosition = SolarCalc.position(t, lat, lon);
    const s = new Sample();
    s.utcMs = t;
    s.altitude = pos.altitudeDeg;
    s.azimuth = pos.azimuthDeg;
    out.push(s);
  }
  return out;
}

/**
 * 全天太阳高度曲线（Canvas）。
 * 地平线以下部分用弱化描边表示，选定时刻以实心圆标注。
 */
@Component
export struct SunPathChart {
  @Prop @Watch('onDataChanged') lat: number = 0;
  @Prop @Watch('onDataChanged') lon: number = 0;
  @Prop @Watch('onDataChanged') tzId: string = 'Asia/Shanghai';
  @Prop @Watch('onDataChanged') dayStartUtc: number = 0;
  @Prop @Watch('onDataChanged') dayEndUtc: number = 0;
  @Prop @Watch('onDataChanged') selectedUtc: number = 0;
  @Prop goldenUpper: number = 6;
  @Prop goldenLower: number = -4;
  @Prop blueLower: number = -6;
  @Prop chartHeight: number = 220;
  onPickTime: (utcMs: number) => void = () => {
  };

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private colors: ThemeColors = new ThemeColors();
  private ready: boolean = false;

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) {
      this.colors = ThemeColors.load(host as common.Context);
    }
  }

  onDataChanged(): void {
    this.redraw();
  }

  private redraw(): void {
    if (this.ready) {
      this.draw();
    }
  }

  /** 当前真实时间轴（draw 时按 dayStart/dayEnd 重建） */
  private tm: TimelineModel = new TimelineModel();

  private xOf(utcMs: number, width: number): number {
    const ratio = this.tm.ratioOf(utcMs);
    if (ratio < 0) {
      return -1;
    }
    return 8 + ratio * (width - 16);
  }

  private yOf(altitude: number, height: number): number {
    const top = 14;
    const bottom = height - 22;
    const clamped = Math.max(-90, Math.min(90, altitude));
    return bottom - ((clamped + 90) / 180.0) * (bottom - top);
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = ctx.width;
    const h = ctx.height;
    ctx.clearRect(0, 0, w, h);
    if (w <= 0 || h <= 0) {
      return;
    }
    // 真实区间；不可用时只画空状态，绝不用 24 小时兜底
    this.tm = Timeline.fromBounds(this.dayStartUtc, this.dayEndUtc);
    if (!this.tm.valid) {
      ctx.fillStyle = this.colors.muted;
      ctx.font = `${FontSize.CAPTION}vp sans-serif`;
      ctx.fillText('当日时间轴不可用', 12, h / 2);
      return;
    }

    // 背景网格
    ctx.strokeStyle = this.colors.line;
    ctx.lineWidth = 1;
    const gridAlts: number[] = [60, 30, 0, -30, -60];
    for (const alt of gridAlts) {
      const y = this.yOf(alt, h);
      ctx.beginPath();
      ctx.moveTo(8, y);
      ctx.lineTo(w - 8, y);
      ctx.stroke();
    }

    // 地平线
    const horizonY = this.yOf(0, h);
    ctx.strokeStyle = this.colors.muted;
    ctx.lineWidth = 1.8;
    ctx.beginPath();
    ctx.moveTo(8, horizonY);
    ctx.lineTo(w - 8, horizonY);
    ctx.stroke();

    // 采样曲线（按真实本地日区间）
    const samples = sampleRange(this.tm.startUtc, this.tm.endUtc, this.lat, this.lon, 10);
    // 地平线以上：强调色
    ctx.strokeStyle = this.colors.accent;
    ctx.lineWidth = 2.2;
    ctx.beginPath();
    let started = false;
    for (const s of samples) {
      const x = this.xOf(s.utcMs, w);
      const y = this.yOf(s.altitude, h);
      if (s.altitude >= 0) {
        if (!started) {
          ctx.moveTo(x, y);
          started = true;
        } else {
          ctx.lineTo(x, y);
        }
      } else {
        started = false;
      }
    }
    ctx.stroke();

    // 地平线以下：弱化
    ctx.strokeStyle = this.colors.muted;
    ctx.lineWidth = 1.2;
    ctx.beginPath();
    started = false;
    for (const s of samples) {
      const x = this.xOf(s.utcMs, w);
      const y = this.yOf(s.altitude, h);
      if (s.altitude < 0) {
        if (!started) {
          ctx.moveTo(x, y);
          started = true;
        } else {
          ctx.lineTo(x, y);
        }
      } else {
        started = false;
      }
    }
    ctx.stroke();

    // 黄金时刻横向带
    const bandTop = this.yOf(this.goldenUpper, h);
    const bandBottom = this.yOf(this.goldenLower, h);
    ctx.fillStyle = this.withAlpha(this.colors.primary, 0.16);
    ctx.fillRect(8, bandTop, w - 16, Math.max(2, bandBottom - bandTop));

    // 选中时刻：必须落在真实区间内才绘制（区间外不画错误标记）
    const selRatio = this.tm.ratioOf(this.selectedUtc);
    if (selRatio >= 0) {
      const pos = SolarCalc.position(this.selectedUtc, this.lat, this.lon);
      const x = 8 + selRatio * (w - 16);
      const y = this.yOf(pos.altitudeDeg, h);
      ctx.strokeStyle = this.withAlpha(this.colors.ink, 0.35);
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(x, 10);
      ctx.lineTo(x, h - 20);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(x, y, 6, 0, Math.PI * 2);
      ctx.fillStyle = this.colors.primary;
      ctx.fill();
      ctx.strokeStyle = this.colors.bg;
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    // 时间刻度：横轴是 UTC 连续时间，标签只做 UTC → 本地 转换。
    // DST 缺口不会出现不存在的本地时刻；回拨造成的重复小时带偏移后缀区分。
    ctx.fillStyle = this.colors.muted;
    ctx.font = `${FontSize.CAPTION}vp sans-serif`;
    const ticks: TimelineTick[] = TimelineLabels.ticks(this.tm, this.tzId, w);
    for (const tick of ticks) {
      const x = 8 + tick.ratio * (w - 16);
      if (x > 4 && x < w - 26) {
        ctx.fillText(tick.label, x, h - 6);
      }
    }
  }

  private withAlpha(hex: string, alpha: number): string {
    const r = Number.parseInt(hex.substring(1, 3), 16);
    const g = Number.parseInt(hex.substring(3, 5), 16);
    const b = Number.parseInt(hex.substring(5, 7), 16);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height(this.chartHeight)
      .backgroundColor(Color.Transparent)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
      .onAreaChange(() => {
        this.redraw();
      })
      .accessibilityText(`全天太阳高度曲线，地点纬度 ${this.lat.toFixed(2)} 度`)
  }
}

/** 罗盘刻度盘 */
@Component
export struct CompassDial {
  @Prop @Watch('onDataChanged') sunAzimuth: number = 0;
  @Prop sunAltitude: number = 0;
  @Prop @Watch('onDataChanged') deviceHeading: number = -1;
  @Prop @Watch('onDataChanged') correction: number = 0;
  @Prop dialSize: number = 260;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private colors: ThemeColors = new ThemeColors();
  private ready: boolean = false;

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) {
      this.colors = ThemeColors.load(host as common.Context);
    }
  }

  onDataChanged(): void {
    this.redraw();
  }

  private redraw(): void {
    if (this.ready) {
      this.draw();
    }
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = ctx.width;
    const h = ctx.height;
    ctx.clearRect(0, 0, w, h);
    const cx = w / 2;
    const cy = h / 2;
    const radius = Math.min(w, h) / 2 - 16;
    if (radius <= 10) {
      return;
    }

    // 外圈
    ctx.strokeStyle = this.colors.line;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.stroke();

    // 刻度：每 30°
    for (let deg = 0; deg < 360; deg += 30) {
      const rad = (deg - 90) * Math.PI / 180;
      const inner = radius - (deg % 90 === 0 ? 14 : 7);
      ctx.strokeStyle = deg % 90 === 0 ? this.colors.muted : this.colors.line;
      ctx.lineWidth = 1.4;
      ctx.beginPath();
      ctx.moveTo(cx + Math.cos(rad) * inner, cy + Math.sin(rad) * inner);
      ctx.lineTo(cx + Math.cos(rad) * radius, cy + Math.sin(rad) * radius);
      ctx.stroke();
    }

    // 方位文字
    ctx.font = `${FontSize.BODY}vp sans-serif`;
    ctx.fillStyle = this.colors.ink;
    const cardinals: string[] = ['N', 'E', 'S', 'W'];
    for (let i = 0; i < 4; i++) {
      const rad = (i * 90 - 90) * Math.PI / 180;
      const tx = cx + Math.cos(rad) * (radius - 30);
      const ty = cy + Math.sin(rad) * (radius - 30) + 6;
      ctx.fillStyle = i === 0 ? this.colors.primary : this.colors.muted;
      ctx.fillText(cardinals[i], tx - 4, ty);
    }

    // 太阳方位射线
    const sunRad = (this.sunAzimuth - 90) * Math.PI / 180;
    ctx.strokeStyle = this.colors.primary;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.lineTo(cx + Math.cos(sunRad) * (radius - 26), cy + Math.sin(sunRad) * (radius - 26));
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(cx + Math.cos(sunRad) * (radius - 18), cy + Math.sin(sunRad) * (radius - 18), 7, 0, Math.PI * 2);
    ctx.fillStyle = this.colors.primary;
    ctx.fill();

    // 设备朝向（含手动校正）
    if (this.deviceHeading >= 0) {
      const devRad = (this.deviceHeading + this.correction - 90) * Math.PI / 180;
      ctx.strokeStyle = this.colors.accent;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(cx - Math.cos(devRad) * 16, cy - Math.sin(devRad) * 16);
      ctx.lineTo(cx + Math.cos(devRad) * (radius - 40), cy + Math.sin(devRad) * (radius - 40));
      ctx.stroke();
    }

    // 中心读数
    ctx.fillStyle = this.colors.panel2;
    ctx.beginPath();
    ctx.arc(cx, cy, 34, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = this.colors.ink;
    ctx.font = `${FontSize.BODY_L}vp sans-serif`;
    const text = `${Math.round(this.sunAzimuth)}°`;
    ctx.fillText(text, cx - 16, cy + 6);
  }

  build() {
    Canvas(this.ctx)
      .width(this.dialSize)
      .height(this.dialSize)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
      .onAreaChange(() => {
        this.redraw();
      })
      .accessibilityText(`罗盘，太阳方位 ${this.sunAzimuth.toFixed(0)} 度`)
  }
}

/** 方位示意图（Map Kit 降级路径：以当前机位为圆心按真实经纬度绘制相对方位） */
@Component
export struct BearingDiagram {
  @Prop @Watch('onDataChanged') centerLat: number = 0;
  @Prop @Watch('onDataChanged') centerLon: number = 0;
  @Prop @Watch('onDataChanged') targetAzimuth: number = 0;
  @Prop @Watch('onDataChanged') radiusDeg: number = 0.5;
  @Prop labelText: string = '';
  /** 其它点位：分号分隔的 lat,lon,name */
  @Prop @Watch('onDataChanged') extraPoints: string = '';
  @Prop diagramHeight: number = 260;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private colors: ThemeColors = new ThemeColors();
  private ready: boolean = false;

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) {
      this.colors = ThemeColors.load(host as common.Context);
    }
  }

  onDataChanged(): void {
    this.redraw();
  }

  private redraw(): void {
    if (this.ready) {
      this.draw();
    }
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = ctx.width;
    const h = ctx.height;
    ctx.clearRect(0, 0, w, h);
    const cx = w / 2;
    const cy = h / 2;
    const radius = Math.min(w, h) / 2 - 24;
    if (radius <= 10) {
      return;
    }

    // 同心圈
    ctx.strokeStyle = this.colors.line;
    ctx.lineWidth = 1;
    for (let i = 1; i <= 3; i++) {
      ctx.beginPath();
      ctx.arc(cx, cy, radius * i / 3, 0, Math.PI * 2);
      ctx.stroke();
    }
    // 十字
    ctx.beginPath();
    ctx.moveTo(cx - radius, cy);
    ctx.lineTo(cx + radius, cy);
    ctx.moveTo(cx, cy - radius);
    ctx.lineTo(cx, cy + radius);
    ctx.stroke();

    // 方位标注
    ctx.fillStyle = this.colors.muted;
    ctx.font = `${FontSize.CAPTION}vp sans-serif`;
    ctx.fillText('N', cx - 4, cy - radius + 10);
    ctx.fillText('S', cx - 4, cy + radius - 2);
    ctx.fillText('E', cx + radius - 8, cy - 4);
    ctx.fillText('W', cx - radius + 2, cy - 4);

    // 比例尺：radiusDeg 对应半径
    const pxPerDeg = radius / Math.max(0.0001, this.radiusDeg);

    // 其它点位（真实经纬度换算相对方位）
    if (this.extraPoints.length > 0) {
      const items: string[] = this.extraPoints.split(';');
      for (const item of items) {
        const parts: string[] = item.split(',');
        if (parts.length < 3) {
          continue;
        }
        const lat = Number.parseFloat(parts[0]);
        const lon = Number.parseFloat(parts[1]);
        const dLat = lat - this.centerLat;
        const dLon = (lon - this.centerLon) * Math.cos(this.centerLat * Math.PI / 180);
        const x = cx + dLon * pxPerDeg;
        const y = cy - dLat * pxPerDeg;
        ctx.beginPath();
        ctx.arc(x, y, 5, 0, Math.PI * 2);
        ctx.fillStyle = this.colors.accent;
        ctx.fill();
        ctx.fillStyle = this.colors.ink;
        ctx.font = `${FontSize.CAPTION}vp sans-serif`;
        ctx.fillText(parts[2], x + 8, y + 4);
      }
    }

    // 目标方向射线
    const rad = (this.targetAzimuth - 90) * Math.PI / 180;
    ctx.strokeStyle = this.colors.primary;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.lineTo(cx + Math.cos(rad) * (radius - 6), cy + Math.sin(rad) * (radius - 6));
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(cx, cy, 6, 0, Math.PI * 2);
    ctx.fillStyle = this.colors.primary;
    ctx.fill();

    ctx.fillStyle = this.colors.muted;
    ctx.font = `${FontSize.CAPTION}vp sans-serif`;
    ctx.fillText(this.labelText, 8, h - 8);
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height(this.diagramHeight)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
      .onAreaChange(() => {
        this.redraw();
      })
      .accessibilityText('机位方位示意图')
  }
}

/** 多日期高度曲线对照 */
export class CompareSeries {
  label: string = '';
  colorHex: string = '';
  lat: number = 0;
  lon: number = 0;
  tzId: string = 'Asia/Shanghai';
  dayStartUtc: number = 0;
  /** 该日期自身的真实本地日结束时刻；<= dayStartUtc 表示该日期不可用 */
  dayEndUtc: number = 0;
}

@Component
export struct CompareChart {
  @Prop seriesToken: number = 0;
  series: CompareSeries[] = [];
  @Prop chartHeight: number = 240;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private colors: ThemeColors = new ThemeColors();
  private ready: boolean = false;

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext();
    if (host !== undefined) {
      this.colors = ThemeColors.load(host as common.Context);
    }
  }

  onTokenChanged(): void {
    this.redraw();
  }

  private redraw(): void {
    if (this.ready) {
      this.draw();
    }
  }

  private draw(): void {
    const ctx = this.ctx;
    const w = ctx.width;
    const h = ctx.height;
    ctx.clearRect(0, 0, w, h);
    if (w <= 0 || h <= 0) {
      return;
    }
    const top = 14;
    const bottom = h - 22;
    const xOf = (ratio: number): number => 8 + ratio * (w - 16);
    const yOf = (alt: number): number => bottom - ((Math.max(-90, Math.min(90, alt)) + 90) / 180) * (bottom - top);

    ctx.strokeStyle = this.colors.line;
    ctx.lineWidth = 1;
    for (const alt of [60, 30, 0, -30, -60]) {
      ctx.beginPath();
      ctx.moveTo(8, yOf(alt));
      ctx.lineTo(w - 8, yOf(alt));
      ctx.stroke();
    }

    // 横轴语义：各本地日「已过去的真实时间比例」，不同日长不能混用钟点标注
    let drewAny = false;
    for (const s of this.series) {
      const model: TimelineModel = Timeline.fromBounds(s.dayStartUtc, s.dayEndUtc);
      if (!model.valid) {
        continue;
      }
      drewAny = true;
      const samples = sampleRange(model.startUtc, model.endUtc, s.lat, s.lon, 15);
      ctx.strokeStyle = s.colorHex;
      ctx.lineWidth = 2;
      ctx.beginPath();
      let started = false;
      for (const sample of samples) {
        const ratio = model.ratioOf(sample.utcMs);
        if (ratio < 0) {
          continue;
        }
        const x = xOf(ratio);
        const y = yOf(sample.altitude);
        if (sample.altitude >= -0.833) {
          if (!started) {
            ctx.moveTo(x, y);
            started = true;
          } else {
            ctx.lineTo(x, y);
          }
        } else {
          started = false;
        }
      }
      ctx.stroke();
    }

    ctx.fillStyle = this.colors.muted;
    ctx.font = `${FontSize.CAPTION}vp sans-serif`;
    if (!drewAny) {
      ctx.fillText('没有可用的对照日期', 12, h / 2);
    }
    ctx.fillText('0%', 8, h - 6);
    ctx.fillText('25%', xOf(0.25), h - 6);
    ctx.fillText('50%', xOf(0.5) - 8, h - 6);
    ctx.fillText('75%', xOf(0.75) - 8, h - 6);
    ctx.fillText('100%', w - 34, h - 6);
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height(this.chartHeight)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
      .onAreaChange(() => {
        this.redraw();
      })
  }
}
