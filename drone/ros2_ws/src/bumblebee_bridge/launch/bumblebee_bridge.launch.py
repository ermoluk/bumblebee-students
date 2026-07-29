from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    mode_arg = DeclareLaunchArgument('mode', default_value='manual',
                                     description='Controller mode: manual or auto')

    controller_node = Node(
        package='bumblebee_bridge',
        executable='bumblebee_controller',
        name='bumblebee_unified_controller',
        output='screen',
        parameters=[{'mode': LaunchConfiguration('mode')}],
        respawn=True,
        respawn_delay=5.0,
    )

    return LaunchDescription([mode_arg, controller_node])
