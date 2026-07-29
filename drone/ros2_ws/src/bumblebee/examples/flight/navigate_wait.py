"""
navigate_wait.py -- minimal example using navigate_wait directly.

Shows how to use the low-level navigate_wait function from drone.py
when you need full control over speed, tolerance, and frame_id.

Uses drone.py library. Run: python3 navigate_wait.py
"""

import sys
sys.path.insert(0, '/home/lb/catkin_ws/src/bumblebee/bumblebee/examples')
import drone

# Take off 1 meter above the ground using body frame (relative)
drone.navigate_wait(z=1, frame_id='body', auto_arm=True, phase='TAKEOFF')

# Fly 1 meter forward relative to the drone current heading
drone.navigate_wait(x=1, frame_id='body', phase='FORWARD')

# Land
drone.safe_land()
