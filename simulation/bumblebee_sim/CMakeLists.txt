cmake_minimum_required(VERSION 3.8)
project(bumblebee_sim)

find_package(ament_cmake REQUIRED)

install(DIRECTORY launch DESTINATION share/${PROJECT_NAME})
install(DIRECTORY worlds DESTINATION share/${PROJECT_NAME})
install(DIRECTORY models DESTINATION share/${PROJECT_NAME})
install(DIRECTORY map    DESTINATION share/${PROJECT_NAME})
install(DIRECTORY python DESTINATION share/${PROJECT_NAME})
install(DIRECTORY scripts DESTINATION share/${PROJECT_NAME} USE_SOURCE_PERMISSIONS)

# Install pose_to_tf as an executable so launch can `Node(executable=...)` it.
install(PROGRAMS python/pose_to_tf.py
        DESTINATION lib/${PROJECT_NAME}
        RENAME pose_to_tf)

# Helper scripts (setup_env.sh, run_sim.sh) installed with executable bit.
install(PROGRAMS scripts/setup_env.sh scripts/run_sim.sh
        DESTINATION lib/${PROJECT_NAME})

ament_package()
