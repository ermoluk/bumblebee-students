#!/usr/bin/env python3

import rospy
from mavros_msgs.msg import RCIn
from bumblebee_bridge.hardware import BumblebeeBoard
import time

class BumblebeeRemoteControl:
    def __init__(self):
        rospy.init_node('bumblebee_remote_control')

        # Инициализация нашей платы через I2C
        try:
            self.bee = BumblebeeBoard()
            rospy.loginfo("Плата Шмеля инициализирована для управления с пульта")
        except Exception as e:
            rospy.logerr(f"Не удалось инициализировать плату: {e}")
            return

        # Подписка на RC каналы от MAVROS
        # Убедись, что mavros запущен и публикует в этот топик
        self.sub = rospy.Subscriber('/mavros/rc/in', RCIn, self.rc_callback)

        # Переменные для защиты (Fail-safe)
        self.last_rc_time = rospy.get_time()
        
        # Настройка частоты публикации (необязательно, но полезно для стабильности)
        self.rate = rospy.Rate(20) 

    def map_value(self, x, in_min, in_max, out_min, out_max):
        """Функция для перевода диапазона RC (1000-2000) в байты (0-255)"""
        # Ограничиваем входные значения
        x = max(in_min, min(in_max, x))
        return int((x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min)

    def rc_callback(self, msg):
        if len(msg.channels) < 9:
            return

        # Берем каналы:
        # Канал 9 (индекс 8) -> Колеса (WHEEL)
        # Канал 7 (индекс 6) -> Прищепка (CLAMP)
        rc_wheel = msg.channels[8]
        rc_clamp = msg.channels[6]

        # --- Логика для Колес (0-255, 128 - стоп) ---
        # Если стик в центре (1500 +/- мертвая зона), ставим 128
        if 1450 <= rc_wheel <= 1550:
            bee_wheel = 128
        else:
            # Преобразуем 1000-2000 в 0-255
            # Внимание: если едет не в ту сторону, поменяй 0 и 255 местами
            bee_wheel = self.map_value(rc_wheel, 1000, 2000, 0, 255)

        # --- Логика для Прищепки (0-255, 128 - центр) ---
        bee_clamp = self.map_value(rc_clamp, 1000, 2000, 0, 255)

        # Отправляем команды на плату
        try:
            self.bee.set_wheels(bee_wheel)
            
            self.bee.set_clamp(bee_clamp)
            
        except Exception as e:
            rospy.logwarn(f"Ошибка I2C при управлении: {e}")

        self.last_rc_time = rospy.get_time()

    def run(self):
        rospy.loginfo("Управление с пульта запущено. Жду данные от MAVROS...")
        while not rospy.is_shutdown():
            # Fail-safe: если пульт пропал более чем на 0.5 сек, стоп
            if rospy.get_time() - self.last_rc_time > 0.5:
                self.bee.set_wheels(128)
            
            # Раз в секунду можно выводить температуру для контроля
            if int(rospy.get_time()) % 5 == 0:
                t = self.bee.get_temps()
                if t:
                    rospy.loginfo(f"Статус: DC={t[0]}C, Main={t[1]}C")
                time.sleep(1) # Чтобы не спамить лог внутри этой секунды

            self.rate.sleep()

if __name__ == '__main__':
    try:
        controller = BumblebeeRemoteControl()
        controller.run()
    except rospy.ROSInterruptException:
        pass