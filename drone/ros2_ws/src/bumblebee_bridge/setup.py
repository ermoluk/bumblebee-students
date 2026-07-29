from setuptools import setup
import os
from glob import glob

package_name = 'bumblebee_bridge'

setup(
    name=package_name,
    version='0.0.2',
    packages=[package_name],
    package_dir={'': 'src'},
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('share', package_name, 'launch'), glob('launch/*.py')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='user',
    maintainer_email='user@todo.todo',
    description='Driver for Bumblebee board via I2C (ROS 2)',
    license='MIT',
    entry_points={
        'console_scripts': [
            'bumblebee_controller = bumblebee_bridge.bumblebee_start:main',
        ],
    },
)
