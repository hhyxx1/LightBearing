import solarCalcTest from './SolarCalc.test';
import solarEventsTest from './SolarEvents.test';
import timeUtilTest from './TimeUtil.test';
import reverseSearchTest from './ReverseSearch.test';
import csvCodecTest from './CsvCodec.test';
import timelineTest from './Timeline.test';
import timeSelectionTest from './TimeSelection.test';

export default function testsuite() {
  solarCalcTest();
  solarEventsTest();
  timeUtilTest();
  reverseSearchTest();
  csvCodecTest();
  timelineTest();
  timeSelectionTest();
}
