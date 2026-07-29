/*
 * Detecting and pose estimation of ArUco markers (ROS2 Jazzy port)
 * Copyright (C) 2018 Copter Express Technologies
 * Author: Oleg Kalachev <okalachev@gmail.com>
 * Distributed under MIT License
 */

#include <math.h>
#include <vector>
#include <string>
#include <map>
#include <unordered_map>
#include <unordered_set>

#include <rclcpp/rclcpp.hpp>
#include <tf2_ros/buffer.h>
#include <tf2_ros/transform_listener.h>
#include <tf2_ros/transform_broadcaster.h>
#include <tf2_geometry_msgs/tf2_geometry_msgs.hpp>
#include <image_transport/image_transport.hpp>
#include <cv_bridge/cv_bridge.hpp>
#include <geometry_msgs/msg/vector3.hpp>
#include <geometry_msgs/msg/pose.hpp>
#include <geometry_msgs/msg/pose_stamped.hpp>
#include <geometry_msgs/msg/pose_with_covariance_stamped.hpp>
#include <geometry_msgs/msg/transform_stamped.hpp>
#include <visualization_msgs/msg/marker.hpp>
#include <visualization_msgs/msg/marker_array.hpp>
#include <sensor_msgs/msg/image.hpp>
#include <sensor_msgs/msg/camera_info.hpp>

#include <opencv2/opencv.hpp>
#include <opencv2/aruco.hpp>

#include <aruco_pose/msg/marker.hpp>
#include <aruco_pose/msg/marker_array.hpp>
#include <aruco_pose/srv/set_markers.hpp>

#include "draw.h"
#include "utils.h"

using std::vector;
using cv::Mat;

class ArucoDetect : public rclcpp::Node {
public:
    ArucoDetect() : Node("aruco_detect"),
                    tf_buffer_(this->get_clock()),
                    tf_listener_(tf_buffer_),
                    br_(this)
    {
        int dictionary = this->declare_parameter("dictionary", 2);
        estimate_poses_ = this->declare_parameter("estimate_poses", true);
        send_tf_ = this->declare_parameter("send_tf", true);
        use_map_markers_ = this->declare_parameter("use_map_markers", false);
        waiting_for_map_ = use_map_markers_;

        if (estimate_poses_) {
            this->declare_parameter("length", 0.15);
            if (!this->get_parameter("length", length_)) {
                RCLCPP_FATAL(this->get_logger(), "can't estimate marker's poses: ~length not defined");
                throw std::runtime_error("length param required");
            }
        }

        readLengthOverride();
        transform_timeout_ = rclcpp::Duration::from_seconds(
            this->declare_parameter("transform_timeout", 0.02));
        known_vertical_ = this->declare_parameter("known_vertical", std::string(""));
        flip_vertical_ = this->declare_parameter("flip_vertical", false);
        auto_flip_ = this->declare_parameter("auto_flip", false);
        frame_id_prefix_ = this->declare_parameter("frame_id_prefix", std::string("aruco_"));

        camera_matrix_ = cv::Mat::zeros(3, 3, CV_64F);
        dictionary_ = cv::aruco::getPredefinedDictionary(
            static_cast<cv::aruco::PREDEFINED_DICTIONARY_NAME>(dictionary));

#if CV_VERSION_MAJOR > 4 || (CV_VERSION_MAJOR == 4 && CV_VERSION_MINOR >= 7)
        parameters_ = cv::makePtr<cv::aruco::DetectorParameters>();
#else
        parameters_ = cv::aruco::DetectorParameters::create();
#endif

        // Detector parameter declarations
        setupDetectorParams();

        // Publishers
        markers_pub_ = this->create_publisher<aruco_pose::msg::MarkerArray>("aruco_detect/markers", 1);
        vis_markers_pub_ = this->create_publisher<visualization_msgs::msg::MarkerArray>("aruco_detect/visualization", 1);
        debug_pub_ = image_transport::create_publisher(this, "aruco_detect/debug");

        // Subscribers
        img_sub_ = image_transport::create_camera_subscription(
            this, "main_camera/image_raw",
            std::bind(&ArucoDetect::imageCallback, this, std::placeholders::_1, std::placeholders::_2),
            "raw");

        map_markers_sub_ = this->create_subscription<aruco_pose::msg::MarkerArray>(
            "aruco_map/map", 1,
            std::bind(&ArucoDetect::mapMarkersCallback, this, std::placeholders::_1));

        // Service
        set_markers_srv_ = this->create_service<aruco_pose::srv::SetMarkers>(
            "aruco_detect/set_length_override",
            std::bind(&ArucoDetect::setMarkers, this, std::placeholders::_1, std::placeholders::_2));

        // Parameter callback for runtime changes
        param_cb_ = this->add_on_set_parameters_callback(
            std::bind(&ArucoDetect::paramCallback, this, std::placeholders::_1));

        RCLCPP_INFO(this->get_logger(), "aruco_detect ready");
    }

private:
    tf2_ros::Buffer tf_buffer_;
    tf2_ros::TransformListener tf_listener_;
    tf2_ros::TransformBroadcaster br_;
    rclcpp::Duration transform_timeout_{0, 0};

    bool enabled_ = true;
    cv::Ptr<cv::aruco::Dictionary> dictionary_;
    cv::Ptr<cv::aruco::DetectorParameters> parameters_;
    image_transport::Publisher debug_pub_;
    image_transport::CameraSubscriber img_sub_;
    rclcpp::Publisher<aruco_pose::msg::MarkerArray>::SharedPtr markers_pub_;
    rclcpp::Publisher<visualization_msgs::msg::MarkerArray>::SharedPtr vis_markers_pub_;
    rclcpp::Subscription<aruco_pose::msg::MarkerArray>::SharedPtr map_markers_sub_;
    rclcpp::Service<aruco_pose::srv::SetMarkers>::SharedPtr set_markers_srv_;
    rclcpp::node_interfaces::OnSetParametersCallbackHandle::SharedPtr param_cb_;

    bool estimate_poses_, send_tf_, flip_vertical_, auto_flip_, use_map_markers_, waiting_for_map_;
    double length_;
    std::unordered_map<int, double> length_override_;
    std::string frame_id_prefix_, known_vertical_;
    Mat camera_matrix_, dist_coeffs_;
    aruco_pose::msg::MarkerArray array_;
    std::unordered_set<int> map_markers_ids_;
    visualization_msgs::msg::MarkerArray vis_array_;

    void setupDetectorParams()
    {
        this->get_parameter("length", length_);
        this->declare_parameter("enabled", true);
        this->declare_parameter("adaptive_thresh_constant", parameters_->adaptiveThreshConstant);
        this->declare_parameter("adaptive_thresh_win_size_min", parameters_->adaptiveThreshWinSizeMin);
        this->declare_parameter("adaptive_thresh_win_size_max", parameters_->adaptiveThreshWinSizeMax);
        this->declare_parameter("adaptive_thresh_win_size_step", parameters_->adaptiveThreshWinSizeStep);
        this->declare_parameter("corner_refinement_max_iterations", parameters_->cornerRefinementMaxIterations);
        this->declare_parameter("corner_refinement_method", parameters_->cornerRefinementMethod);
        this->declare_parameter("corner_refinement_min_accuracy", parameters_->cornerRefinementMinAccuracy);
        this->declare_parameter("corner_refinement_win_size", parameters_->cornerRefinementWinSize);
        this->declare_parameter("error_correction_rate", parameters_->errorCorrectionRate);
        this->declare_parameter("min_corner_distance_rate", parameters_->minCornerDistanceRate);
        this->declare_parameter("marker_border_bits", parameters_->markerBorderBits);
        this->declare_parameter("max_erroneous_bits_in_border_rate", parameters_->maxErroneousBitsInBorderRate);
        this->declare_parameter("min_distance_to_border", parameters_->minDistanceToBorder);
        this->declare_parameter("min_marker_distance_rate", parameters_->minMarkerDistanceRate);
        this->declare_parameter("min_marker_perimeter_rate", parameters_->minMarkerPerimeterRate);
        this->declare_parameter("max_marker_perimeter_rate", parameters_->maxMarkerPerimeterRate);
        this->declare_parameter("min_otsu_std_dev", parameters_->minOtsuStdDev);
        this->declare_parameter("perspective_remove_ignored_margin_per_cell",
                                parameters_->perspectiveRemoveIgnoredMarginPerCell);
        this->declare_parameter("perspective_remove_pixel_per_cell", parameters_->perspectiveRemovePixelPerCell);
        this->declare_parameter("polygonal_approx_accuracy_rate", parameters_->polygonalApproxAccuracyRate);
    }

    rcl_interfaces::msg::SetParametersResult paramCallback(
        const std::vector<rclcpp::Parameter>& params)
    {
        for (const auto& p : params) {
            if (p.get_name() == "enabled") { enabled_ = p.as_bool() && length_ > 0; }
            else if (p.get_name() == "length") { length_ = p.as_double(); enabled_ = length_ > 0; }
            else if (p.get_name() == "adaptive_thresh_constant") parameters_->adaptiveThreshConstant = p.as_double();
            else if (p.get_name() == "adaptive_thresh_win_size_min") parameters_->adaptiveThreshWinSizeMin = p.as_int();
            else if (p.get_name() == "adaptive_thresh_win_size_max") parameters_->adaptiveThreshWinSizeMax = p.as_int();
            else if (p.get_name() == "adaptive_thresh_win_size_step") parameters_->adaptiveThreshWinSizeStep = p.as_int();
            else if (p.get_name() == "corner_refinement_max_iterations") parameters_->cornerRefinementMaxIterations = p.as_int();
            else if (p.get_name() == "corner_refinement_method") parameters_->cornerRefinementMethod = p.as_int();
            else if (p.get_name() == "corner_refinement_min_accuracy") parameters_->cornerRefinementMinAccuracy = p.as_double();
            else if (p.get_name() == "corner_refinement_win_size") parameters_->cornerRefinementWinSize = p.as_int();
            else if (p.get_name() == "error_correction_rate") parameters_->errorCorrectionRate = p.as_double();
            else if (p.get_name() == "min_corner_distance_rate") parameters_->minCornerDistanceRate = p.as_double();
            else if (p.get_name() == "marker_border_bits") parameters_->markerBorderBits = p.as_int();
            else if (p.get_name() == "max_erroneous_bits_in_border_rate") parameters_->maxErroneousBitsInBorderRate = p.as_double();
            else if (p.get_name() == "min_distance_to_border") parameters_->minDistanceToBorder = p.as_int();
            else if (p.get_name() == "min_marker_distance_rate") parameters_->minMarkerDistanceRate = p.as_double();
            else if (p.get_name() == "min_marker_perimeter_rate") parameters_->minMarkerPerimeterRate = p.as_double();
            else if (p.get_name() == "max_marker_perimeter_rate") parameters_->maxMarkerPerimeterRate = p.as_double();
            else if (p.get_name() == "min_otsu_std_dev") parameters_->minOtsuStdDev = p.as_double();
            else if (p.get_name() == "perspective_remove_ignored_margin_per_cell") parameters_->perspectiveRemoveIgnoredMarginPerCell = p.as_double();
            else if (p.get_name() == "perspective_remove_pixel_per_cell") parameters_->perspectiveRemovePixelPerCell = p.as_int();
            else if (p.get_name() == "polygonal_approx_accuracy_rate") parameters_->polygonalApproxAccuracyRate = p.as_double();
        }
        rcl_interfaces::msg::SetParametersResult result;
        result.successful = true;
        return result;
    }

    void imageCallback(const sensor_msgs::msg::Image::ConstSharedPtr& msg,
                       const sensor_msgs::msg::CameraInfo::ConstSharedPtr& cinfo)
    {
        if (!enabled_) return;
        if (waiting_for_map_) return;

        Mat image = cv_bridge::toCvShare(msg)->image;

        vector<int> ids;
        vector<vector<cv::Point2f>> corners, rejected;
        vector<cv::Vec3d> rvecs, tvecs;
        geometry_msgs::msg::TransformStamped vertical;

        cv::aruco::detectMarkers(image, dictionary_, corners, ids, parameters_, rejected);

        array_.header.stamp = msg->header.stamp;
        array_.header.frame_id = msg->header.frame_id;
        array_.markers.clear();

        if (!ids.empty()) {
            parseCameraInfo(cinfo, camera_matrix_, dist_coeffs_);

            if (estimate_poses_) {
                cv::aruco::estimatePoseSingleMarkers(corners, length_, camera_matrix_, dist_coeffs_,
                                                     rvecs, tvecs);

                if (!length_override_.empty()) {
                    for (unsigned int i = 0; i < ids.size(); i++) {
                        auto item = length_override_.find(ids[i]);
                        if (item != length_override_.end()) {
                            vector<cv::Vec3d> r, t;
                            vector<vector<cv::Point2f>> c = {corners[i]};
                            cv::aruco::estimatePoseSingleMarkers(c, item->second, camera_matrix_, dist_coeffs_, r, t);
                            rvecs[i] = r[0];
                            tvecs[i] = t[0];
                        }
                    }
                }

                if (!known_vertical_.empty()) {
                    try {
                        vertical = tf_buffer_.lookupTransform(msg->header.frame_id, known_vertical_,
                                                              rclcpp::Time(msg->header.stamp),
                                                              tf2::durationFromSec(transform_timeout_.seconds()));
                    } catch (const tf2::TransformException& e) {
                        RCLCPP_WARN_THROTTLE(this->get_logger(), *this->get_clock(), 5000,
                                             "can't retrieve known vertical: %s", e.what());
                    }
                }
            }

            array_.markers.reserve(ids.size());
            aruco_pose::msg::Marker marker;
            vector<geometry_msgs::msg::TransformStamped> transforms;
            transforms.reserve(ids.size());
            geometry_msgs::msg::TransformStamped transform;
            transform.header.stamp = msg->header.stamp;
            transform.header.frame_id = msg->header.frame_id;

            for (unsigned int i = 0; i < ids.size(); i++) {
                marker.id = ids[i];
                marker.length = getMarkerLength(ids[i]);
                fillCorners(marker, corners[i]);

                if (estimate_poses_) {
                    fillPose(marker.pose, rvecs[i], tvecs[i]);

                    if (!known_vertical_.empty() && !vertical.header.frame_id.empty()) {
                        applyVertical(marker.pose.orientation, vertical.transform.rotation, false, auto_flip_);
                    }

                    if (send_tf_) {
                        transform.child_frame_id = getChildFrameId(ids[i]);
                        if (map_markers_ids_.find(ids[i]) == map_markers_ids_.end()) {
                            bool send = true;
                            for (auto& t : transforms) {
                                if (t.child_frame_id == transform.child_frame_id) { send = false; break; }
                            }
                            if (send) {
                                transform.transform.rotation = marker.pose.orientation;
                                fillTranslation(transform.transform.translation, tvecs[i]);
                                transforms.push_back(transform);
                            }
                        }
                    }
                }
                array_.markers.push_back(marker);
            }

            if (send_tf_ && !transforms.empty()) br_.sendTransform(transforms);
        }

        markers_pub_->publish(array_);

        if (estimate_poses_ && vis_markers_pub_->get_subscription_count() > 0) {
            visualization_msgs::msg::Marker del;
            del.action = visualization_msgs::msg::Marker::DELETEALL;
            vis_array_.markers.clear();
            vis_array_.markers.push_back(del);
            for (unsigned int i = 0; i < ids.size(); i++) {
                pushVisMarkers(msg->header.frame_id, msg->header.stamp,
                               array_.markers[i].pose, getMarkerLength(ids[i]), ids[i], i);
            }
            vis_markers_pub_->publish(vis_array_);
        }

        if (debug_pub_.getNumSubscribers() > 0) {
            Mat debug = image.clone();
            cv::aruco::drawDetectedMarkers(debug, corners, ids);
            if (estimate_poses_) {
                for (unsigned int i = 0; i < ids.size(); i++) {
                    _drawAxis(debug, camera_matrix_, dist_coeffs_, rvecs[i], tvecs[i], getMarkerLength(ids[i]));
                }
            }
            cv_bridge::CvImage out;
            out.header.frame_id = msg->header.frame_id;
            out.header.stamp = msg->header.stamp;
            out.encoding = sensor_msgs::image_encodings::BGR8;
            out.image = debug;
            debug_pub_.publish(out.toImageMsg());
        }
    }

    inline void fillCorners(aruco_pose::msg::Marker& marker,
                            const vector<cv::Point2f>& corners) const
    {
        marker.c1.x = corners[0].x; marker.c1.y = corners[0].y;
        marker.c2.x = corners[1].x; marker.c2.y = corners[1].y;
        marker.c3.x = corners[2].x; marker.c3.y = corners[2].y;
        marker.c4.x = corners[3].x; marker.c4.y = corners[3].y;
    }

    void pushVisMarkers(const std::string& frame_id, const builtin_interfaces::msg::Time& stamp,
                        const geometry_msgs::msg::Pose& pose, double length, int id, int index)
    {
        visualization_msgs::msg::Marker marker;
        marker.header.frame_id = frame_id;
        marker.header.stamp = stamp;
        marker.action = visualization_msgs::msg::Marker::ADD;
        marker.id = index;
        marker.ns = "aruco_marker";
        marker.type = visualization_msgs::msg::Marker::CUBE;
        marker.scale.x = length; marker.scale.y = length; marker.scale.z = 0.001;
        marker.color.r = 1; marker.color.g = 1; marker.color.b = 1; marker.color.a = 0.9;
        marker.pose = pose;
        vis_array_.markers.push_back(marker);

        marker.ns = "aruco_marker_label";
        marker.type = visualization_msgs::msg::Marker::TEXT_VIEW_FACING;
        marker.scale.z = length * 0.6;
        marker.color.r = 0; marker.color.g = 0; marker.color.b = 0; marker.color.a = 1;
        marker.text = std::to_string(id);
        vis_array_.markers.push_back(marker);
    }

    inline std::string getChildFrameId(int id) const
    {
        return frame_id_prefix_ + std::to_string(id);
    }

    void readLengthOverride()
    {
        // Length override as "length_override.ID: value" parameters
        // e.g. ros2 param set /aruco_detect length_override.5 0.3
    }

    inline double getMarkerLength(int id)
    {
        auto item = length_override_.find(id);
        return (item != length_override_.end()) ? item->second : length_;
    }

    void setMarkers(const std::shared_ptr<aruco_pose::srv::SetMarkers::Request> req,
                    std::shared_ptr<aruco_pose::srv::SetMarkers::Response> res)
    {
        for (auto const& marker : req->markers) {
            if (marker.id > 999) {
                res->message = "Invalid marker id: " + std::to_string(marker.id);
                RCLCPP_ERROR(this->get_logger(), "%s", res->message.c_str());
                return;
            }
            if (!std::isfinite(marker.length) || marker.length <= 0) {
                res->message = "Invalid marker " + std::to_string(marker.id) + " length";
                RCLCPP_ERROR(this->get_logger(), "%s", res->message.c_str());
                return;
            }
        }
        for (auto const& marker : req->markers) {
            length_override_[marker.id] = marker.length;
        }
        res->success = true;
    }

    void mapMarkersCallback(const aruco_pose::msg::MarkerArray::SharedPtr msg)
    {
        map_markers_ids_.clear();
        for (auto const& marker : msg->markers) {
            map_markers_ids_.insert(marker.id);
            if (use_map_markers_) {
                if (length_override_.find(marker.id) == length_override_.end()) {
                    length_override_[marker.id] = marker.length;
                }
            }
        }
        waiting_for_map_ = false;
    }
};

int main(int argc, char** argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<ArucoDetect>());
    rclcpp::shutdown();
    return 0;
}
