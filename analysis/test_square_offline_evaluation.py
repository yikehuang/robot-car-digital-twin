"""Behavioral checks for offline evaluation; uses synthetic temporary CSVs only."""
from pathlib import Path
import argparse
import csv
import math
import subprocess
import tempfile
import unittest

HEADER='trial,direction,stage,state,reason,time_ms,left_count,right_count,x_mm,y_mm,theta_rad,left_pwm,right_pwm\n'
JAVA=None
CLASSPATH=None

def frame(trial,stamp,state=1,reason='straight',direction='CW'):
    return f'{trial},{direction},0,{state},{reason},{stamp},0,0,0,0,0,0,0\n'

class OfflineEvaluationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='square-offline-')
        self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name)

    def evaluate(self,content,label=None):
        source=self.base/'telemetry.csv';source.write_text(HEADER+content,encoding='utf-8')
        output=self.base/'results'
        args=[JAVA,'-Djava.awt.headless=true','-cp',CLASSPATH,'SquareReplayEvaluation',str(source),str(output)]
        if label:args.append(label)
        result=subprocess.run(args,capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)
        if label:
            return output
        with (output/'square_metrics.csv').open(encoding='utf-8') as stream:
            metrics=list(csv.DictReader(stream))
        with (output/'square_trace.csv').open(encoding='utf-8') as stream:
            trace=list(csv.DictReader(stream))
        return metrics,trace

    def test_robot_stops_first_preserve_same_time_gap(self):
        metrics,trace=self.evaluate(frame(0,0,0,'waiting')+frame(1,100)+frame(1,200,2,'complete'))
        self.assertEqual(len(metrics),1)
        m=metrics[0]
        self.assertEqual(int(m['robot_stop_ms']),100)
        self.assertGreater(int(m['twin_stop_ms']),100)
        self.assertEqual(int(trace[-1]['twin_pose_ms']),100)
        self.assertAlmostEqual(float(m['completion_time_delta_ms']),int(m['twin_stop_ms'])-100)
        self.assertGreater(abs(float(m['position_gap_at_robot_stop_mm'])-float(m['completion_endpoint_gap_mm'])),1)

    def test_model_stops_first_hold_terminal_pose(self):
        metrics,trace=self.evaluate(frame(0,0,0,'waiting')+frame(1,10)+frame(1,20010,2,'complete'))
        m=metrics[0]
        self.assertLess(int(m['twin_stop_ms']),20000)
        self.assertEqual(int(trace[-1]['twin_pose_ms']),int(m['twin_stop_ms']))
        self.assertLess(int(m['completion_time_delta_ms']),0)

    def test_failure_keeps_first_stop_and_no_success_comparison(self):
        metrics,_=self.evaluate(frame(0,0,0,'waiting')+frame(1,10)+frame(1,110,3,'left_stalled')+frame(1,210,3,'remote_stop'))
        self.assertEqual(len(metrics),1)
        self.assertEqual(metrics[0]['robot_stop_reason'],'left_stalled')
        for field in ('completion_time_delta_ms','completion_endpoint_gap_mm','completion_heading_delta_deg'):
            self.assertEqual(metrics[0][field],'')

    def test_mid_run_without_idle_is_excluded(self):
        metrics,trace=self.evaluate(frame(1,100)+frame(1,200,2,'complete'))
        self.assertEqual(metrics,[]);self.assertEqual(trace,[])

    def test_missing_terminal_record_has_trace_but_no_metrics(self):
        metrics,trace=self.evaluate(frame(0,0,0,'waiting')+frame(1,100)+frame(1,200))
        self.assertEqual(metrics,[]);self.assertEqual(len(trace),2)

    def test_wrong_turn_direction_is_excluded(self):
        metrics,trace=self.evaluate(frame(0,0,0,'waiting')+frame(1,100,direction='CCW')+frame(1,200,2,'complete',direction='CCW'))
        self.assertEqual(metrics,[]);self.assertEqual(trace,[])

    def test_reboot_with_same_trial_gets_distinct_run_numbers(self):
        run=frame(0,0,0,'waiting')+frame(1,100)+frame(1,200,2,'complete')
        metrics,_=self.evaluate(run+run)
        self.assertEqual([m['run'] for m in metrics],['1','2'])
        self.assertTrue(all(math.isfinite(float(m['position_rmse_mm'])) for m in metrics))

    def test_three_argument_legacy_interface(self):
        output=self.evaluate(frame(0,0,0,'waiting')+frame(1,100)+frame(1,200,2,'complete'),label='compatibility')
        self.assertTrue((output/'compatibility_metrics.csv').is_file())
        self.assertTrue((output/'compatibility_trace.csv').is_file())

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--java',required=True)
    parser.add_argument('--classpath',required=True)
    options=parser.parse_args()
    JAVA,CLASSPATH=options.java,options.classpath
    unittest.main(argv=['test_square_offline_evaluation'],verbosity=2)
