import { sensor } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x1003;
const TAG = 'LB_SENSOR';

/** 罗盘读数 */
export class CompassReading {
  /** 设备绕 Z 轴旋转角（0-360°），作为朝向参考 */
  alphaDeg: number = 0;
  betaDeg: number = 0;
  gammaDeg: number = 0;
  /** 采样时间（纳秒） */
  timestampNs: number = 0;
}

/**
 * 现场罗盘传感器。
 *
 * 重要：手机磁力传感器只能给出设备姿态的相对角度，受磁偏角、金属与磁体干扰，
 * 因此 UI 必须标注「仅作参考」，并允许用户手动校正偏移量。
 */
export class SensorService {
  private static listening: boolean = false;
  private static callback: ((reading: CompassReading) => void) | undefined = undefined;

  /** 设备是否具备方向传感器 */
  static async hasCompass(): Promise<boolean> {
    try {
      const list = await sensor.getSensorList();
      for (const s of list) {
        if (s.sensorId === sensor.SensorId.ORIENTATION) {
          return true;
        }
      }
      return false;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'getSensorList failed %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /** 开始订阅；返回是否成功 */
  static start(onReading: (reading: CompassReading) => void): boolean {
    if (SensorService.listening) {
      SensorService.stop();
    }
    SensorService.callback = onReading;
    try {
      sensor.on(sensor.SensorType.SENSOR_TYPE_ID_ORIENTATION, (data: sensor.OrientationResponse) => {
        const cb = SensorService.callback;
        if (cb !== undefined) {
          const r = new CompassReading();
          r.alphaDeg = data.alpha;
          r.betaDeg = data.beta;
          r.gammaDeg = data.gamma;
          r.timestampNs = data.timestamp;
          cb(r);
        }
      }, { interval: 100000000 });
      SensorService.listening = true;
      return true;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'sensor.on failed code=%{public}d msg=%{public}s', e.code, e.message);
      SensorService.listening = false;
      return false;
    }
  }

  static stop(): void {
    if (!SensorService.listening) {
      return;
    }
    try {
      sensor.off(sensor.SensorType.SENSOR_TYPE_ID_ORIENTATION);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'sensor.off failed');
    }
    SensorService.listening = false;
    SensorService.callback = undefined;
  }

  static isListening(): boolean {
    return SensorService.listening;
  }
}
