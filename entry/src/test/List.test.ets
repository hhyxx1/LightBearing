import solarCalcTest from './SolarCalc.test';
import reverseSearchTest from './ReverseSearch.test';
import csvCodecTest from './CsvCodec.test';

export default function testsuite() {
  solarCalcTest();
  reverseSearchTest();
  csvCodecTest();
}
