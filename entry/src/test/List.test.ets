import solarCalcTest from './SolarCalc.test';
import solarEventsTest from './SolarEvents.test';
import reverseSearchTest from './ReverseSearch.test';
import csvCodecTest from './CsvCodec.test';

export default function testsuite() {
  solarCalcTest();
  solarEventsTest();
  reverseSearchTest();
  csvCodecTest();
}
