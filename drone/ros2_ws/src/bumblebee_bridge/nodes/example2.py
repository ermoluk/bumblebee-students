# Copyright 2026 FutureLab
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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