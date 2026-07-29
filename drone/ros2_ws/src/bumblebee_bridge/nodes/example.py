#!/usr/bin/env python3
import rospy
import time
from std_msgs.msg import UInt8, Int32MultiArray

class MissionControl:
    def __init__(self):
        rospy.init_node('bumblebee_mission')

        # --- Настройка паблишеров (Куда отправляем команды) ---
        # Обрати внимание: имена топиков должны совпадать с тем, как запущена нода драйвера.
        # Если драйвер запущен как bumblebee_driver, то топики будут:
        self.pub_wheel = rospy.Publisher('/bumblebee_driver/wheel', UInt8, queue_size=1)
        self.pub_clamp = rospy.Publisher('/bumblebee_driver/clamp', UInt8, queue_size=1)

        # --- Настройка подписчика (Откуда читаем данные) ---
        rospy.Subscriber('/bumblebee_driver/temp', Int32MultiArray, self.temp_callback)
        
        self.current_temps = [0, 0]
        
        # Ждем, пока ROS поднимет соединения
        time.sleep(1)

    def temp_callback(self, msg):
        self.current_temps = msg.data

    def stop_robot(self):
        """Безопасная остановка: 128 - это стоп для колес [cite: 11]"""
        rospy.loginfo("Остановка робота...")
        self.pub_wheel.publish(128)

    def run_mission(self):
        # Гарантируем остановку при выходе из программы
        rospy.on_shutdown(self.stop_robot)

        rospy.loginfo("=== НАЧАЛО МИССИИ ===")
        
        # 1. Проверка систем
        rospy.loginfo(f"Температура DC: {self.current_temps[0]}C, MAIN: {self.current_temps[1]}C [cite: 28]")
        
        # 2. Работа клешней (Прищепочница)
        # 0 - крайнее положение, 255 - другое крайнее положение [cite: 10, 11]
        rospy.loginfo("Сжимаю захват (значение 255)...")
        self.pub_clamp.publish(255) 
        time.sleep(2.0)

        # 3. Движение вперед
        # 255 - полный газ вперед, 128 - стоп. Дадим средний газ (180) [cite: 11]
        rospy.loginfo("Поехали вперед (скорость 180)...")
        self.pub_wheel.publish(180)
        
        # Едем 2 секунды
        time.sleep(2.0)

        # 4. Остановка
        rospy.loginfo("Стоп!")
        self.pub_wheel.publish(128) # [cite: 11]
        time.sleep(0.5)

        # 5. Разжать захват
        rospy.loginfo("Разжимаю захват (значение 0)...")
        self.pub_clamp.publish(0) # [cite: 10]
        time.sleep(1.0)
        
        # Возврат в нейтральное положение захвата
        self.pub_clamp.publish(128) # [cite: 11]

        rospy.loginfo("=== МИССИЯ ЗАВЕРШЕНА ===")

if __name__ == '__main__':
    try:
        controller = MissionControl()
        controller.run_mission()
    except rospy.ROSInterruptException:
        pass