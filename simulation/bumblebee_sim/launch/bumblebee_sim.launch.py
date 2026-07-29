"""
bumblebee_sim.launch.py — sim variant of bumblebee.launch.py.

Differences vs production launch:
  * MAVROS connects to PX4 SITL via UDP (fcu_url=udp://:14540@127.0.0.1:14557)
  * No v4l2_camera / camera_fix — camera comes from Gazebo via ros_gz_image bridge
  * No bumblebee_bridge / wheel_init / servo_rc / wheel_rc / optical_flow (I2C / RC stubs)
  * aruco_detect + vpe_fix instantiated directly (no aruco_pose package dependency)
  * Dashboard nodes (rosbridge, mjpeg, tf2_web_republisher, static HTTP) all enabled
  * ros_gz_image_bridge + ros_gz parameter_bridge (camera_info, /clock)
  * use_sim_time=True forwarded to all nodes
"""
import os
from launch import LaunchDescription
from launch.actions import (
    DeclareLaunchArgument,
    ExecuteProcess,
    IncludeLaunchDescription,
    OpaqueFunction,
    TimerAction,
    SetEnvironmentVariable,
)
from launch.conditions import IfCondition
from launch.launch_description_sources import AnyLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node, SetParameter
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():
    args = [
        DeclareLaunchArgument(
            'fcu_url', default_value='udp://:14540@127.0.0.1:14580',
            description='MAVROS FCU URL for PX4 SITL (PX4 listens on 14580, sends to 14540)'),
        DeclareLaunchArgument(
            'gz_world', default_value='clover_aruco',
            description='Gazebo world name used in the ros_gz topic path'),
        DeclareLaunchArgument(
            'gz_model', default_value='x500_mono_cam_down_0',
            description='Vehicle model name in the Gazebo world (PX4 4014 spawns x500_mono_cam_down_0)'),
        DeclareLaunchArgument(
            'gz_camera_link', default_value='camera_link',
            description='Link name carrying the downward camera sensor'),
        DeclareLaunchArgument(
            'gz_camera_topic_suffix', default_value='/sensor/imager/image',
            description='Suffix appended after model+link path for image topic'),
        DeclareLaunchArgument('rosbridge', default_value='true'),
        DeclareLaunchArgument('web_video_server', default_value='true'),
        DeclareLaunchArgument('aruco', default_value='true'),
        DeclareLaunchArgument(
            'http_port', default_value='8000',
            description='Port for the static dashboard HTTP server'),
    ]

    fcu_url = LaunchConfiguration('fcu_url')
    gz_world = LaunchConfiguration('gz_world')
    gz_model = LaunchConfiguration('gz_model')
    gz_camera_link = LaunchConfiguration('gz_camera_link')
    gz_camera_topic_suffix = LaunchConfiguration('gz_camera_topic_suffix')
    http_port = LaunchConfiguration('http_port')

    # All nodes use simulated /clock so MAVROS heartbeat timeout, simple_offboard
    # state staleness checks, and TF stamps line up. Bridged via the gz
    # parameter_bridge below (/clock topic).
    use_sim_time = SetParameter(name='use_sim_time', value=True)

    # ── MAVROS ──────────────────────────────────────────────────────────────
    # The production mavros_config.yaml is in legacy ROS 1 layout (no
    # `ros__parameters:` wrapper) so we cannot pass it directly. Inline the
    # subset that matters for SITL flight + ArUco vision pose.
    mavros_node = Node(
        package='mavros',
        executable='mavros_node',
        name='mavros',
        output='screen',
        respawn=True,
        respawn_delay=5.0,
        parameters=[{
            'fcu_url': fcu_url,
            'target_system_id': 1,
            'target_component_id': 1,
            # PX4 SITL with gz_bridge runs sim time slower than real (10–60×
            # slower on weak hosts). PX4 heartbeats in sim-time, so MAVROS must
            # also tick on sim-time — otherwise its hardcoded ~10s heartbeat
            # timeout fires before the next sim-time heartbeat arrives.
            'use_sim_time': True,
            # MAVROS publishes map -> base_link TF when local_position.tf.send
            # is on. simple_offboard's get_telemetry uses that TF chain.
            'local_position.tf.send': True,
            'local_position.tf.frame_id': 'map',
            'local_position.tf.child_frame_id': 'base_link',
        }],
    )

    # ── SIMPLE OFFBOARD ─────────────────────────────────────────────────────
    simple_offboard = Node(
        package='bumblebee',
        executable='simple_offboard',
        name='simple_offboard',
        output='screen',
        parameters=[{
            'reference_frames.main_camera_optical': 'map',
            # SITL: no rangefinder; fall back to /mavros/altitude
            'terrain_frame_mode': 'altitude',
            'arming_timeout': 15.0,
        }],
        remappings=[
            ('/mavros/local_position/pose', '/mavros/mavros/pose'),
            ('/mavros/local_position/velocity_body', '/mavros/mavros/velocity_body'),
            ('/mavros/cmd/arming', '/mavros/mavros/arming'),
            ('/mavros/setpoint_position/local', '/mavros/mavros/local'),
            ('/mavros/setpoint_attitude/cmd_vel', '/mavros/mavros/cmd_vel'),
            ('/mavros/setpoint_attitude/thrust', '/mavros/mavros/thrust'),
        ],
    )

    # ── DYNAMIC TF: map → base_link from MAVROS pose ────────────────────────
    # MAVROS 2.x's local_position.tf.send requires a per-plugin YAML config
    # that's hard to inline. This shim subscribes to /mavros/mavros/pose and
    # broadcasts map -> base_link directly so simple_offboard's TF lookups work.
    pose_to_tf = Node(
        package='bumblebee_sim',
        executable='pose_to_tf',
        name='pose_to_tf',
        output='screen',
        parameters=[{
            'input_topic': '/mavros/mavros/pose',
            'parent_frame': 'map',
            'child_frame': 'base_link',
        }],
    )

    # ── STATIC TF: base_link → main_camera_optical (matches production) ─────
    main_camera_frame = Node(
        package='tf2_ros',
        executable='static_transform_publisher',
        name='main_camera_frame',
        arguments=['0.05', '0', '-0.07', '-1.5707963', '0', '3.1415926',
                   'base_link', 'main_camera_optical'],
    )

    # ── ARUCO DETECT — instantiated directly (avoid aruco_pose package) ─────
    map_path = PathJoinSubstitution([
        FindPackageShare('bumblebee_sim'), 'map', 'sim_default.txt',
    ])
    aruco_detect = Node(
        package='bumblebee',
        executable='aruco_detect.py',
        name='aruco_detect',
        output='screen',
        respawn=True,
        respawn_delay=1.0,
        condition=IfCondition(LaunchConfiguration('aruco')),
        parameters=[{
            'dictionary': 1,                    # DICT_4X4_100
            # Sim: no CPU gating - detect markers continuously so the
            # pre-arm ArUco preflight (require_aruco) can pass on the ground.
            'gate_by_flight_state': False,
            'estimate_poses': True,
            'send_tf': True,
            'use_map_markers': True,
            'length': 0.19,
            'corner_refinement_method': 3,
            'corner_refinement_win_size': 7,
            'min_marker_perimeter_rate': 0.02,
            'adaptive_thresh_win_size_max': 83,
            'polygonal_approx_accuracy_rate': 0.08,
            'perspective_remove_pixel_per_cell': 8,
            'max_erroneous_bits_in_border_rate': 0.50,
            'error_correction_rate': 0.80,
            'use_clahe': True,
            'max_reproj_error_px': 15.0,
            'pose_smooth_alpha': 0.5,
            'tracker_timeout_sec': 0.3,
            'multi_scale': True,
            'map_file': map_path,
        }],
        remappings=[
            ('image_raw',    'main_camera/image_raw'),
            ('camera_info',  'main_camera/camera_info'),
            ('map_markers',  'aruco_map/map'),
            ('markers',      'aruco_detect/markers'),
            ('debug',        'aruco_detect/debug'),
            ('map_pose',     'aruco_map/pose'),
            ('map_image',    'aruco_map/image'),
        ],
    )

    vpe_publisher = Node(
        package='bumblebee',
        executable='vpe_fix.py',
        name='vpe_publisher',
        output='screen',
        respawn=True,
        respawn_delay=5.0,
        condition=IfCondition(LaunchConfiguration('aruco')),
    )

    # ── CAMERA MARKERS (overlay ArUco hits on image stream) ─────────────────
    camera_markers = Node(
        package='bumblebee',
        executable='camera_markers',
        name='main_camera_markers',
        namespace='main_camera',
        parameters=[{'scale': 3.0}],
    )

    # Delay aruco/vpe by 5s so MAVROS + camera bridge are publishing.
    aruco_delayed = TimerAction(period=5.0, actions=[aruco_detect, vpe_publisher])

    # ── ROS_GZ BRIDGES — sim camera + clock ─────────────────────────────────
    # Built inside OpaqueFunction because remapping tuples need concrete
    # strings, not lists of substitutions.
    def _make_gz_bridges(context):
        world = context.perform_substitution(gz_world)
        model = context.perform_substitution(gz_model)
        link = context.perform_substitution(gz_camera_link)
        suffix = context.perform_substitution(gz_camera_topic_suffix)
        image_topic = f'/world/{world}/model/{model}/link/{link}{suffix}'
        info_topic = f'/world/{world}/model/{model}/link/{link}/sensor/imager/camera_info'
        return [
            Node(
                package='ros_gz_image',
                executable='image_bridge',
                name='gz_image_bridge',
                output='screen',
                arguments=[image_topic],
                remappings=[(image_topic, '/main_camera/image_raw')],
            ),
            Node(
                package='ros_gz_bridge',
                executable='parameter_bridge',
                name='gz_param_bridge',
                output='screen',
                arguments=[
                    '/clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock',
                    f'{info_topic}@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo',
                ],
                remappings=[(info_topic, '/main_camera/camera_info')],
            ),
        ]

    gz_bridges = OpaqueFunction(function=_make_gz_bridges)

    # ── QOS RELAY (BEST_EFFORT → RELIABLE for rosbridge subscribers) ────────
    qos_relay = Node(
        package='bumblebee',
        executable='qos_relay.py',
        name='qos_relay',
        output='screen',
        respawn=True,
        respawn_delay=5.0,
    )

    # ── SET PARAMS ──────────────────────────────────────────────────────────
    set_params = Node(
        package='bumblebee',
        executable='set_params.py',
        name='set_params',
        output='screen',
    )

    # ── DASHBOARD: MJPEG video server ───────────────────────────────────────
    web_video_server = Node(
        package='bumblebee',
        executable='ros_mjpeg_server.py',
        name='ros_mjpeg_server',
        output='screen',
        respawn=True,
        respawn_delay=5.0,
        condition=IfCondition(LaunchConfiguration('web_video_server')),
    )

    # ── DASHBOARD: rosbridge_websocket :9090 ────────────────────────────────
    rosbridge_launch = IncludeLaunchDescription(
        AnyLaunchDescriptionSource(
            PathJoinSubstitution([
                FindPackageShare('rosbridge_server'),
                'launch', 'rosbridge_websocket_launch.xml',
            ])
        ),
        condition=IfCondition(LaunchConfiguration('rosbridge')),
    )

    tf2_web_republisher = Node(
        package='tf2_web_republisher',
        executable='tf2_web_republisher_node',
        name='tf2_web_republisher',
        output='screen',
        condition=IfCondition(LaunchConfiguration('rosbridge')),
    )

    # ── DASHBOARD: static HTTP for the production www/gcs.html ──────────────
    # Uses an OpaqueFunction so the port LaunchConfiguration is resolved into
    # a concrete string before we hand the cmd list to ExecuteProcess.
    def _make_http(context):
        port = context.perform_substitution(http_port)
        return [ExecuteProcess(
            cmd=['bash', '-c',
                 'cd "$(ros2 pkg prefix bumblebee)/share/bumblebee/www" && '
                 f'python3 -m http.server {port} --bind 0.0.0.0'],
            output='screen',
        )]

    www_http = OpaqueFunction(function=_make_http)

    return LaunchDescription(args + [
        use_sim_time,
        SetEnvironmentVariable(
            'ROS_DOMAIN_ID', os.environ.get('ROS_DOMAIN_ID', '0')),
        mavros_node,
        simple_offboard,
        pose_to_tf,
        qos_relay,
        main_camera_frame,
        camera_markers,
        aruco_delayed,
        gz_bridges,
        set_params,
        web_video_server,
        rosbridge_launch,
        tf2_web_republisher,
        www_http,
    ])
