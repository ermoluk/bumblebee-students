#!/usr/bin/env python3
"""Demo: play all preset tunes through PX4 buzzer via MAVROS."""

import time
import drone

PRESETS = [
    ('BEEP',     drone.TUNE_BEEP,           'QBASIC'),
    ('OK',       drone.TUNE_OK,             'QBASIC'),
    ('ERROR',    drone.TUNE_ERROR,          'QBASIC'),
    ('NOTIFY',   drone.TUNE_NOTIFY,         'QBASIC'),
    ('ARMING',   drone.TUNE_ARMING,         'QBASIC'),
    ('IMPERIAL', drone.TUNE_IMPERIAL_MARCH, 'QBASIC'),
    ('MARIO',    drone.TUNE_MARIO,          'QBASIC'),
    ('TETRIS',   drone.TUNE_TETRIS,         'QBASIC'),
]

for name, tune, fmt in PRESETS:
    print('Playing:', name)
    drone.play_tune(tune, fmt)
    time.sleep(4.0)
