import { describe, beforeAll, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x2001;
const TAG = 'LB_UITEST';
const BUNDLE = 'com.hhyxx.lightbearing';

/**
 * UI 自动化测试。
 *
 * 关键点：测试进程不会自动把被测应用切到前台，必须先通过 AbilityDelegator 拉起
 * EntryAbility，再让 UiTest Driver 断言界面元素。
 */
export default function uiTest() {
  describe('LightBearingUI', () => {
    beforeAll(async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const want: Want = {
        bundleName: BUNDLE,
        abilityName: 'EntryAbility'
      };
      try {
        await delegator.startAbility(want);
        hilog.info(DOMAIN, TAG, 'ability started');
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'startAbility failed: %{public}s', JSON.stringify(err));
      }
      const driver = Driver.create();
      await driver.delayMs(3000);
    });

    it('home_page_renders', 0, async (done: Function) => {
      const driver = Driver.create();
      await driver.delayMs(2000);
      try {
        await driver.assertComponentExist(ON.text('今日光线'));
        await driver.assertComponentExist(ON.text('好光线，值得提前抵达'));
        expect(true).assertTrue();
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'home assertions failed: %{public}s', JSON.stringify(err));
        expect(false).assertTrue();
      }
      done();
    });

    it('bottom_nav_to_sunpath', 0, async (done: Function) => {
      const driver = Driver.create();
      await driver.delayMs(1000);
      try {
        const tab = await driver.findComponent(ON.text('轨迹'));
        await tab.click();
        await driver.delayMs(2000);
        await driver.assertComponentExist(ON.text('太阳轨迹'));
        expect(true).assertTrue();
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'nav failed: %{public}s', JSON.stringify(err));
        expect(false).assertTrue();
      }
      done();
    });

    it('open_more_tools_page', 0, async (done: Function) => {
      const driver = Driver.create();
      await driver.delayMs(1000);
      try {
        const more = await driver.findComponent(ON.text('更多'));
        await more.click();
        await driver.delayMs(2000);
        await driver.assertComponentExist(ON.text('更多工具'));
        expect(true).assertTrue();
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'more page failed: %{public}s', JSON.stringify(err));
        expect(false).assertTrue();
      }
      done();
    });
  });
}
