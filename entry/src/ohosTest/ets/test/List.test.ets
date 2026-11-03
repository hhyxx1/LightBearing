import uiTest from './UiTest.test';
import abilityTest from './Ability.test';
import timeZoneRealTest from './TimeZoneReal.test';
import kernelPerfRealTest from './KernelPerfReal.test';

export default function testsuite() {
  abilityTest();
  timeZoneRealTest();
  kernelPerfRealTest();
  uiTest();
}
