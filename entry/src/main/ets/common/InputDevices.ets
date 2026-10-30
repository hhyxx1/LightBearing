import { inputDevice } from '@kit.InputKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x1007;
const TAG = 'LB_INPUT';

/**
 * 输入设备探测。
 *
 * 只用于决定「是否显示物理键盘快捷键提示」——纯触屏设备上不显示，
 * 不参与任何业务计算。
 */
export class InputDevices {
  private static cached: boolean = false;
  private static probed: boolean = false;

  static async hasPhysicalKeyboard(): Promise<boolean> {
    if (InputDevices.probed) {
      return InputDevices.cached;
    }
    try {
      const ids = await inputDevice.getDeviceList();
      let found = false;
      for (const id of ids) {
        const detail = await inputDevice.getDevice(id);
        for (const source of detail.sources) {
          if (`${source}` === 'keyboard') {
            found = true;
          }
        }
      }
      InputDevices.cached = found;
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'getDeviceList failed: %{public}s', e.message);
      InputDevices.cached = false;
    }
    InputDevices.probed = true;
    return InputDevices.cached;
  }
}
