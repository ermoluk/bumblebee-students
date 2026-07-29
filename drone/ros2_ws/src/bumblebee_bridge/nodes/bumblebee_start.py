#!/usr/bin/env python3

import rospy
import time
import sys
from mavros_msgs.msg import RCIn
from std_msgs.msg import Int32MultiArray
from bumblebee_bridge.hardware import BumblebeeBoard

class UnifiedController:
    def __init__(self):
        rospy.init_node('bumblebee_unified_controller')
        
        # Инициализация железа через I2C (адрес 123) [cite: 3, 53]
        try:
            self.bee = BumblebeeBoard()
            rospy.loginfo("Железо Шмеля успешно инициализировано ")
        except Exception as e:
            rospy.logerr(f"Ошибка инициализации I2C: {e}")
            sys.exit(1)

        self.last_rc_time = rospy.get_time()
        self.current_mode = rospy.get_param('~mode', 'manual') # 'manual' или 'auto'
        
        # Подписки
        if self.current_mode == 'manual':
            self.sub_rc = rospy.Subscriber('/mavros/rc/in', RCIn, self.rc_callback)
            rospy.loginfo("Режим: РУЧНОЙ (Пульт через MAVROS)")
        else:
            rospy.loginfo("Режим: АВТОНОМНЫЙ (Выполнение встроенной миссии)")

    def map_value(self, x, in_min, in_max, out_min, out_max):
        """Перевод RC диапазона (1000-2000) в байты (0-255) """
        x = max(in_min, min(in_max, x))
        return int((x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min)

    def rc_callback(self, msg):
        """Обработка команд с пульта"""
        if len(msg.channels) < 9: return

        # Канал 9 -> Колеса, Канал 7 -> Прищепка
        rc_wheel = msg.channels[8]
        rc_clamp = msg.channels[6]

        # Управление колесами: 128 - стоп 
        bee_wheel = 123 if 1450 <= rc_wheel <= 1550 else self.map_value(rc_wheel, 1000, 2000, 0, 255)
        # Управление прищепкой: 128 - центр 
        bee_clamp = self.map_value(rc_clamp, 1000, 2000, 0, 255)

        self.bee.set_wheels(bee_wheel)
        self.bee.set_clamp(bee_clamp)
        self.last_rc_time = rospy.get_time()

    def run_auto_mission(self):
        """Пример встроенной миссии из кода"""
        rospy.loginfo("Начало автономной миссии...")
        
        # Вперед на средней скорости 
        self.bee.set_wheels(180)
        time.sleep(2)
        
        # Остановка и работа захватом [cite: 10, 11]
        self.bee.set_wheels(128)
        self.bee.set_clamp(255) # Закрыть
        time.sleep(1)
        self.bee.set_clamp(0)   # Открыть
        time.sleep(1)
        self.bee.set_clamp(128) # Центр
        
        rospy.loginfo("Автономная миссия завершена")

    def monitor(self):
        """Основной цикл мониторинга"""
        if self.current_mode == 'auto':
            self.run_auto_mission()
            # После миссии переходим в режим ожидания
            while not rospy.is_shutdown():
                self.bee.set_wheels(128)
                rospy.sleep(1)
        else:
            # Цикл для ручного режима с Fail-safe
            rate = rospy.Rate(10)
            while not rospy.is_shutdown():
                # Если пульт пропал > 0.5с - тормозим 
                if rospy.get_time() - self.last_rc_time > 0.5:
                    self.bee.set_wheels(128)
                
                # Каждые 5 секунд выводим температуру 
                if int(rospy.get_time()) % 5 == 0:
                    t = self.bee.get_temps()
                    if t: rospy.loginfo(f"Температура: DC={t[0]}C, Main={t[1]}C")
                    rospy.sleep(1)
                rate.sleep()

if __name__ == '__main__':
    controller = UnifiedController()
    controller.monitor()