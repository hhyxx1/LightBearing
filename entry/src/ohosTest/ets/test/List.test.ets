import uiTest from './UiTest.test';
import abilityTest from './Ability.test';
import timeZoneRealTest from './TimeZoneReal.test';

export default function testsuite() {
  abilityTest();
  timeZoneRealTest();
  uiTest();
}
