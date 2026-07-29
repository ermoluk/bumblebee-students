cmake_minimum_required(VERSION 3.8)
project(aruco_pose)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic -std=c++17)
endif()

find_package(ament_cmake REQUIRED)
find_package(rosidl_default_generators REQUIRED)
find_package(rclcpp REQUIRED)
find_package(tf2 REQUIRED)
find_package(tf2_ros REQUIRED)
find_package(tf2_geometry_msgs REQUIRED)
find_package(cv_bridge REQUIRED)
find_package(image_transport REQUIRED)
find_package(message_filters REQUIRED)
find_package(std_msgs REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(visualization_msgs REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(OpenCV REQUIRED COMPONENTS core imgproc calib3d objdetect)

# Generate messages and services
rosidl_generate_interfaces(${PROJECT_NAME}
  "msg/Point2D.msg"
  "msg/Marker.msg"
  "msg/MarkerArray.msg"
  "srv/SetMarkers.srv"
  DEPENDENCIES std_msgs geometry_msgs
)

rosidl_get_typesupport_target(cpp_typesupport_target ${PROJECT_NAME} "rosidl_typesupport_cpp")

# aruco_detect node
add_executable(aruco_detect src/aruco_detect.cpp src/draw.cpp)
ament_target_dependencies(aruco_detect
  rclcpp tf2 tf2_ros tf2_geometry_msgs
  cv_bridge image_transport sensor_msgs
  geometry_msgs visualization_msgs)
target_include_directories(aruco_detect PUBLIC ${OpenCV_INCLUDE_DIRS})
target_link_libraries(aruco_detect ${OpenCV_LIBS} ${cpp_typesupport_target})

# aruco_map node
add_executable(aruco_map src/aruco_map.cpp src/draw.cpp)
ament_target_dependencies(aruco_map
  rclcpp tf2 tf2_ros tf2_geometry_msgs
  cv_bridge image_transport message_filters sensor_msgs
  geometry_msgs visualization_msgs)
target_include_directories(aruco_map PUBLIC ${OpenCV_INCLUDE_DIRS})
target_link_libraries(aruco_map ${OpenCV_LIBS} ${cpp_typesupport_target})

install(TARGETS aruco_detect aruco_map
  DESTINATION lib/${PROJECT_NAME})

install(DIRECTORY map/
  DESTINATION share/${PROJECT_NAME}/map
  OPTIONAL)

ament_package()
