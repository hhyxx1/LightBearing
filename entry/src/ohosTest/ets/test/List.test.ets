import uiTest from './UiTest.test';
import abilityTest from './Ability.test';

export default function testsuite() {
  abilityTest();
  uiTest();
}
