from bumblebee_bridge.hardware import BumblebeeBoard
import time 
# Инициализация
bee = BumblebeeBoard()

# Примеры управления
bee.set_wheels(0)      # Макс. скорость вперёд
time.sleep(2)

bee.set_wheels(123)    # Макс. скорость назад
time.sleep(2)

bee.set_wheels(256) 
time.sleep(2)

bee.set_wheels(123)
time.sleep(2) 
#================
bee.set_clamp(0)   # Макс. скорость назад
time.sleep(2)

bee.set_clamp(128) 
time.sleep(2)

bee.set_clamp(256)
time.sleep(2) 
# Чтение данных
bee.set_clamp(128) 
time.sleep(2)




temp = bee.get_temps()
if temp:
    print(f"Температура: DC={temp[0]}°C, Основная={temp[1]}°C")

# Остановка и завершение
# bee.stop()
# bee.close()