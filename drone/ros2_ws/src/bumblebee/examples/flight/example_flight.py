"""
example_flight.py -- multi-waypoint example using drone.py library.

Sequence:
    1. Take off to 1m
    2. Fly forward 2m (body frame)
    3. Fly right 1m  (body frame)
    4. Hover 3s
    5. Return to map origin (marker 0)
    6. Land

Uses drone.py library. Run: python3 example_flight.py
"""

import sys
sys.path.insert(0, '/home/lb/catkin_ws/src/bumblebee/bumblebee/examples')
import drone

print('=== Example flight starting ===')

# Step 1: take off to 1m
drone.takeoff(1.0)

# Step 2: move 2m forward relative to current heading
drone.move(x=2.0)

# Step 3: move 1m to the right (negative y = right in body frame)
drone.move(y=-1.0)

# Step 4: hover in place for 3 seconds
drone.hover(3.0)

# Step 5: return to map origin (marker 0)
drone.fly_to(x=0, y=0, z=1.0)

# Step 6: land
drone.safe_land()

print('=== Flight complete ===')
