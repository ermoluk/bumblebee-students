"""Sim stub for the smbus2 package — pure no-op SMBus.

On the real drone smbus2 talks to /dev/i2c-1. On macOS there is no I2C bus,
so the real smbus2 either isn't installed or its writes/reads would error.
This stub satisfies `import smbus2` and exposes a no-op SMBus class that all
example scripts (led.py, shmel_lib.py, shmel_example.py) and drone.py's
internal I2C path can call into without raising.

Reads return a benign zero-filled value of the requested size.
"""

class SMBus:
    def __init__(self, bus=1):
        self._bus = bus
        self.fd = -1  # presence checked by drone.py I2C init

    def close(self):
        pass

    # — write side, all no-ops —
    def write_byte(self, _addr, _value):
        return None

    def write_byte_data(self, _addr, _reg, _value):
        return None

    def write_i2c_block_data(self, _addr, _reg, _data):
        return None

    def write_word_data(self, _addr, _reg, _value):
        return None

    # — read side, return zero-filled — keeps callers from KeyError'ing —
    def read_byte(self, _addr):
        return 0

    def read_byte_data(self, _addr, _reg):
        return 0

    def read_i2c_block_data(self, _addr, _reg, length):
        return [0] * int(length)

    def read_word_data(self, _addr, _reg):
        return 0


# i2c_msg helpers used by some smbus2 callers (not currently used by these
# examples, but cheap to provide so future scripts don't blow up).
class i2c_msg:
    @staticmethod
    def read(_addr, _length):
        return None

    @staticmethod
    def write(_addr, _data):
        return None
