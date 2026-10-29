import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x1002;
const TAG = 'LB_LOC';

/** 一次定位结果（WGS84） */
export class GeoPoint {
  latWgs84: number = 0;
  lonWgs84: number = 0;
  /** 水平精度，米 */
  accuracyM: number = 0;
}

/** 定位失败原因分类，用于 UI 降级提示 */
export class LocationFailure {
  /** 1=权限被拒 2=定位服务关闭 3=超时 4=设备不支持 5=其它 */
  code: number = 0;
  message: string = '';

  static of(code: number, message: string): LocationFailure {
    const f = new LocationFailure();
    f.code = code;
    f.message = message;
    return f;
  }
}

export class LocationResult {
  point: GeoPoint | undefined = undefined;
  failure: LocationFailure | undefined = undefined;
}

const PERMISSIONS: Permissions[] = [
  'ohos.permission.APPROXIMATELY_LOCATION',
  'ohos.permission.LOCATION'
];

/**
 * 前台一次定位。仅在用户主动点击「使用当前位置」时调用；
 * 不做后台定位，不订阅连续位置。
 */
export class LocationService {
  /** 是否已获得定位权限（不触发弹窗） */
  static hasPermission(): boolean {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const tokenId = info.appInfo.accessTokenId;
      const status = atManager.checkAccessTokenSync(tokenId, 'ohos.permission.APPROXIMATELY_LOCATION');
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'hasPermission failed %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /** 申请定位权限，用户拒绝时返回 false（不抛出） */
  static async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, PERMISSIONS);
      for (let i = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] === 0) {
          return true;
        }
      }
      return false;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'requestPermission failed %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /** 定位服务总开关 */
  static isLocationEnabled(): boolean {
    try {
      return geoLocationManager.isLocationEnabled();
    } catch (err) {
      return false;
    }
  }

  /** 获取一次位置；失败返回带原因的结果，调用方据此展示降级路径 */
  static async locateOnce(context: common.UIAbilityContext): Promise<LocationResult> {
    const result = new LocationResult();
    if (!LocationService.isLocationEnabled()) {
      result.failure = LocationFailure.of(2, '系统定位服务已关闭，可在系统设置中开启，或直接手动输入经纬度。');
      return result;
    }
    if (!LocationService.hasPermission()) {
      const granted = await LocationService.requestPermission(context);
      if (!granted) {
        result.failure = LocationFailure.of(1, '未授予定位权限。手动输入经纬度不影响全部计算功能。');
        return result;
      }
    }
    const request: geoLocationManager.CurrentLocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
      scenario: geoLocationManager.LocationRequestScenario.UNSET,
      maxAccuracy: 200,
      timeoutMs: 12000
    };
    try {
      const location = await geoLocationManager.getCurrentLocation(request);
      const point = new GeoPoint();
      point.latWgs84 = location.latitude;
      point.lonWgs84 = location.longitude;
      point.accuracyM = location.accuracy;
      result.point = point;
      return result;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'getCurrentLocation failed code=%{public}d', e.code);
      if (e.code === 3301100) {
        result.failure = LocationFailure.of(2, '系统定位服务未开启，无法取得位置。');
      } else if (e.code === 201) {
        result.failure = LocationFailure.of(1, '定位权限校验失败，请重新授权。');
      } else if (e.code === 801) {
        result.failure = LocationFailure.of(4, '当前设备不支持该定位能力。');
      } else {
        result.failure = LocationFailure.of(3, `定位超时或失败（错误码 ${e.code}）。可重试或手动输入经纬度。`);
      }
      return result;
    }
  }
}
