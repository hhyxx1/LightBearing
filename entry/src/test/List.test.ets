import solarCalcTest from './SolarCalc.test';
import solarEventsTest from './SolarEvents.test';
import timeUtilTest from './TimeUtil.test';
import reverseSearchTest from './ReverseSearch.test';
import csvCodecTest from './CsvCodec.test';
import timelineTest from './Timeline.test';
import timeSelectionTest from './TimeSelection.test';
import reverseSearchBaselineTest from './ReverseSearchBaseline.test';
import reverseSearchSessionTest from './ReverseSearchSession.test';
import searchSessionRegressionTest from './SearchSessionRegression.test';
import searchRunPolicyTest from './SearchRunPolicy.test';
import searchAnomalyAuditTest from './SearchAnomalyAudit.test';
import reverseViewStateTest from './ReverseViewState.test';
import planPlaceGuardTest from './PlanPlaceGuard.test';

export default function testsuite() {
  solarCalcTest();
  solarEventsTest();
  timeUtilTest();
  reverseSearchTest();
  csvCodecTest();
  timelineTest();
  timeSelectionTest();
  reverseSearchBaselineTest();
  reverseSearchSessionTest();
  searchSessionRegressionTest();
  searchRunPolicyTest();
  searchAnomalyAuditTest();
  reverseViewStateTest();
  planPlaceGuardTest();
}
