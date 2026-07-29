#!/usr/bin/env python3
import rospy
from std_msgs.msg import UInt8, Int32MultiArray
from bumblebee_bridge.hardware import BumblebeeBoard

class Node:
    def __init__(self):
        rospy.init_node('bumblebee_driver')
        
        # Инициализация железа (I2C bus 1)
        self.board = BumblebeeBoard(bus_num=1)

        # Подписчики
        rospy.Subscriber('~wheel', UInt8, self.cb_wheel)
        rospy.Subscriber('~clamp', UInt8, self.cb_clamp)
        
        # Паблишер температуры
        self.pub_temp = rospy.Publisher('~temp', Int32MultiArray, queue_size=10)
        
        # Таймер опроса датчиков (10 Гц)
        rospy.Timer(rospy.Duration(0.1), self.timer_cb)

    def cb_wheel(self, msg):
        try:
            self.board.set_wheels(msg.data)
        except Exception as e:
            rospy.logwarn(f"I2C Wheel Error: {e}")

    def cb_clamp(self, msg):
        try:
            self.board.set_clamp(msg.data)
        except Exception as e:
            rospy.logwarn(f"I2C Clamp Error: {e}")

    def timer_cb(self, event):
        try:
            t1, t2 = self.board.get_temps()
            msg = Int32MultiArray(data=[t1, t2])
            self.pub_temp.publish(msg)
        except Exception as e:
            pass # Ошибки чтения игнорируем, чтобы не спамить в лог

if __name__ == '__main__':
    try:
        Node()
        rospy.spin()
    except rospy.ROSInterruptException:
        pass