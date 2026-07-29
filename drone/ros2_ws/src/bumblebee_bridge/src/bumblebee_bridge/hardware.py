import smbus2
import time

class BumblebeeBoard:
    # Используем значения из твоего рабочего примера
    ADDR = 0x7B  # 123 decimal
    REG_WHEEL = 0x01
    REG_CRIMP = 0x02
    REG_TEMP  = 0x03

    def __init__(self, bus_num=1):
        self.bus = smbus2.SMBus(bus_num)

    def set_wheels(self, value):
        try:
            val = max(0, min(255, int(value)))
            self.bus.write_byte_data(self.ADDR, self.REG_WHEEL, val)
            return True
        except Exception as e:
            return False

    def set_clamp(self, value):
        try:
            val = max(0, min(255, int(value)))
            self.bus.write_byte_data(self.ADDR, self.REG_CRIMP, val)
            return True
        except Exception as e:
            return False

    def get_temps(self):
        try:
            # Точная последовательность из твоего примера:
            # 1. Пишем в регистр температуры
            self.bus.write_byte_data(self.ADDR, self.REG_TEMP, 0)
            # 2. Небольшая пауза, чтобы STM32 подготовил данные
            time.sleep(0.02) 
            # 3. Читаем блок из 2 байт
            data = self.bus.read_i2c_block_data(self.ADDR, self.REG_TEMP, 2)
            if len(data) >= 2:
                return data[0], data[1]
            return 0, 0
        except Exception as e:
            return 0, 0