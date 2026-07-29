/*
 * Detecting and pose estimation of ArUco marker maps (ROS2 Jazzy port)
 * Copyright (C) 2018 Copter Express Technologies
 * Author: Oleg Kalachev <okalachev@gmail.com>
 * Distributed under MIT License
 */

#include <math.h>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <memory>

#include <rclcpp/rclcpp.hpp>
#include <image_transport/image_transport.hpp>
#include <cv_bridge/cv_bridge.hpp>
#include <tf2_ros/buffer.h>
#include <tf2_ros/transform_listener.h>
#include <tf2_ros/transform_broadcaster.h>
#include <tf2_ros/static_transform_broadcaster.h>
#include <tf2_geometry_msgs/tf2_geometry_msgs.hpp>
#include <tf2/LinearMath/Quaternion.h>
#include <tf2/LinearMath/Transform.h>
#include <message_filters/subscriber.h>
#include <message_filters/synchronizer.h>
#include <message_filters/sync_policies/exact_time.h>
#include <geometry_msgs/msg/transform_stamped.hpp>
#include <geometry_msgs/msg/pose_with_covariance_stamped.hpp>
#include <sensor_msgs/msg/image.hpp>
#include <sensor_msgs/msg/camera_info.hpp>
#include <visualization_msgs/msg/marker.hpp>
#include <visualization_msgs/msg/marker_array.hpp>

#include <aruco_pose/msg/marker_array.hpp>
#include <aruco_pose/msg/marker.hpp>

#include <opencv2/opencv.hpp>
#include <opencv2/aruco.hpp>

#include "draw.h"
#include "utils.h"

using std::vector;
using cv::Mat;
using sensor_msgs::msg::Image;
using sensor_msgs::msg::CameraInfo;
using aruco_pose::msg::MarkerArray;

typedef message_filters::sync_policies::ExactTime<Image, CameraInfo, MarkerArray> SyncPolicy;

class ArucoMap : public rclcpp::Node {
public:
    ArucoMap() : Node("aruco_map"),
                 tf_buffer_(this->get_clock()),
                 tf_listener_(tf_buffer_),
                 br_(this),
                 static_br_(this)
    {
        int dictionary = this->declare_parameter("dictionary", 2);
        type_ = this->declare_parameter("type", std::string("map"));
        transform_.child_frame_id = this->declare_parameter("frame_id", std::string("aruco_map"));
        known_vertical_ = this->declare_parameter("known_vertical", std::string(""));
        flip_vertical_ = this->declare_parameter("flip_vertical", false);
        auto_flip_ = this->declare_parameter("auto_flip", false);
        image_width_ = this->declare_parameter("image_width", 2000);
        image_height_ = this->declare_parameter("image_height", 2000);
        image_margin_ = this->declare_parameter("image_margin", 200);
        image_axis_ = this->declare_parameter("image_axis", true);
        put_markers_count_to_covariance_ = this->declare_parameter("put_markers_count_to_covariance", false);
        markers_parent_frame_ = this->declare_parameter("markers_frame_id", transform_.child_frame_id);
        markers_frame_ = this->declare_parameter("markers_child_frame_id_prefix", std::string(""));
        enabled_ = this->declare_parameter("enabled", true);

        camera_matrix_ = cv::Mat::zeros(3, 3, CV_64F);

        board_ = cv::makePtr<cv::aruco::Board>();
        board_->dictionary = cv::aruco::getPredefinedDictionary(
            static_cast<cv::aruco::PREDEFINED_DICTIONARY_NAME>(dictionary));

        // Publishers
        img_pub_ = this->create_publisher<sensor_msgs::msg::Image>("aruco_map/image", rclcpp::QoS(1).transient_local());
        markers_pub_ = this->create_publisher<aruco_pose::msg::MarkerArray>("aruco_map/map", rclcpp::QoS(1).transient_local());
        pose_pub_ = this->create_publisher<geometry_msgs::msg::PoseWithCovarianceStamped>("aruco_map/pose", 1);
        vis_markers_pub_ = this->create_publisher<visualization_msgs::msg::MarkerArray>("aruco_map/visualization", rclcpp::QoS(1).transient_local());
        debug_pub_ = image_transport::create_publisher(this, "aruco_map/debug");

        // Load map
        if (type_ == "map") {
            map_ = this->declare_parameter("map", std::string(""));
            loadMap(map_);
        } else if (type_ == "gridboard") {
            createGridBoard();
        } else {
            RCLCPP_FATAL(this->get_logger(), "unknown type: %s", type_.c_str());
            throw std::runtime_error("Unknown aruco_map type");
        }

        publishMap();

        // Synchronized subscribers
        image_sub_.subscribe(this, "image_raw");
        info_sub_.subscribe(this, "camera_info");
        markers_sub_.subscribe(this, "markers");

        sync_ = std::make_shared<message_filters::Synchronizer<SyncPolicy>>(
            SyncPolicy(10), image_sub_, info_sub_, markers_sub_);
        sync_->registerCallback(std::bind(&ArucoMap::callback, this,
                                          std::placeholders::_1, std::placeholders::_2, std::placeholders::_3));

        // Parameter callback
        param_cb_ = this->add_on_set_parameters_callback(
            std::bind(&ArucoMap::paramCallback, this, std::placeholders::_1));

        RCLCPP_INFO(this->get_logger(), "aruco_map ready");
    }

private:
    tf2_ros::Buffer tf_buffer_;
    tf2_ros::TransformListener tf_listener_;
    tf2_ros::TransformBroadcaster br_;
    tf2_ros::StaticTransformBroadcaster static_br_;

    rclcpp::Publisher<sensor_msgs::msg::Image>::SharedPtr img_pub_;
    rclcpp::Publisher<aruco_pose::msg::MarkerArray>::SharedPtr markers_pub_;
    rclcpp::Publisher<geometry_msgs::msg::PoseWithCovarianceStamped>::SharedPtr pose_pub_;
    rclcpp::Publisher<visualization_msgs::msg::MarkerArray>::SharedPtr vis_markers_pub_;
    image_transport::Publisher debug_pub_;

    message_filters::Subscriber<Image> image_sub_;
    message_filters::Subscriber<CameraInfo> info_sub_;
    message_filters::Subscriber<MarkerArray> markers_sub_;
    std::shared_ptr<message_filters::Synchronizer<SyncPolicy>> sync_;

    rclcpp::node_interfaces::OnSetParametersCallbackHandle::SharedPtr param_cb_;

    cv::Ptr<cv::aruco::Board> board_;
    Mat camera_matrix_, dist_coeffs_;
    geometry_msgs::msg::TransformStamped transform_;
    geometry_msgs::msg::PoseWithCovarianceStamped pose_;
    vector<geometry_msgs::msg::TransformStamped> markers_transforms_;
    aruco_pose::msg::MarkerArray markers_;
    visualization_msgs::msg::MarkerArray vis_array_;

    bool enabled_ = true;
    std::string type_, map_, markers_frame_, markers_parent_frame_;
    std::string known_vertical_;
    int image_width_, image_height_, image_margin_;
    bool flip_vertical_, auto_flip_, image_axis_, put_markers_count_to_covariance_;

    // ── Main callback ─────────────────────────────────────────────────────────

    void callback(const Image::ConstSharedPtr& image,
                  const CameraInfo::ConstSharedPtr& cinfo,
                  const MarkerArray::ConstSharedPtr& markers)
    {
        if (!enabled_) return;
        if (markers->markers.empty()) return;

        int valid = 0;
        std::vector<int> ids;
        std::vector<std::vector<cv::Point2f>> corners;
        cv::Vec3d rvec, tvec;

        parseCameraInfo(cinfo, camera_matrix_, dist_coeffs_);

        ids.reserve(markers->markers.size());
        corners.reserve(markers->markers.size());

        if (put_markers_count_to_covariance_) {
            int valid_markers = 0;
            for (auto const& marker : markers->markers) {
                for (auto const& bid : board_->ids) {
                    if (bid == (int)marker.id) { valid_markers++; break; }
                }
            }
            pose_.pose.covariance[0] = valid_markers;
        }

        for (auto const& marker : markers->markers) {
            ids.push_back(marker.id);
            corners.push_back({
                cv::Point2f(marker.c1.x, marker.c1.y),
                cv::Point2f(marker.c2.x, marker.c2.y),
                cv::Point2f(marker.c3.x, marker.c3.y),
                cv::Point2f(marker.c4.x, marker.c4.y)
            });
        }

        if (known_vertical_.empty()) {
            valid = cv::aruco::estimatePoseBoard(corners, ids, board_, camera_matrix_, dist_coeffs_,
                                                 rvec, tvec, false);
            if (!valid) goto publish_debug;

            transform_.header.stamp = markers->header.stamp;
            transform_.header.frame_id = markers->header.frame_id;
            pose_.header = transform_.header;
            fillPose(pose_.pose.pose, rvec, tvec);
            fillTransform(transform_.transform, rvec, tvec);

        } else {
            Mat obj_points, img_points;
            cv::aruco::getBoardObjectAndImagePoints(board_, corners, ids, obj_points, img_points);
            if (obj_points.empty()) goto publish_debug;

            double cx = 0, cy = 0, cz = 0;
            alignObjPointsToCenter(obj_points, cx, cy, cz);

            valid = cv::solvePnP(obj_points, img_points, camera_matrix_, dist_coeffs_, rvec, tvec, false);
            if (!valid) goto publish_debug;

            fillTransform(transform_.transform, rvec, tvec);
            try {
                auto vertical = tf_buffer_.lookupTransform(markers->header.frame_id, known_vertical_,
                                                           rclcpp::Time(markers->header.stamp),
                                                           tf2::durationFromSec(0.02));
                applyVertical(transform_.transform.rotation, vertical.transform.rotation,
                              flip_vertical_, auto_flip_);
            } catch (const tf2::TransformException& e) {
                RCLCPP_WARN_THROTTLE(this->get_logger(), *this->get_clock(), 1000,
                                     "can't retrieve known vertical: %s", e.what());
            }

            geometry_msgs::msg::TransformStamped shift;
            shift.transform.translation.x = -cx;
            shift.transform.translation.y = -cy;
            shift.transform.translation.z = -cz;
            shift.transform.rotation.w = 1;
            tf2::doTransform(shift, transform_, transform_);

            tvec[0] = transform_.transform.translation.x;
            tvec[1] = transform_.transform.translation.y;
            tvec[2] = transform_.transform.translation.z;

            transform_.header.stamp = markers->header.stamp;
            transform_.header.frame_id = markers->header.frame_id;
            pose_.header = transform_.header;
            transformToPose(transform_.transform, pose_.pose.pose);
        }

        if (!transform_.child_frame_id.empty()) br_.sendTransform(transform_);
        pose_pub_->publish(pose_);

    publish_debug:
        if (debug_pub_.getNumSubscribers() > 0) {
            Mat mat = cv_bridge::toCvCopy(image, "bgr8")->image;
            cv::aruco::drawDetectedMarkers(mat, corners, ids);
            if (valid) _drawAxis(mat, camera_matrix_, dist_coeffs_, rvec, tvec, 1.0);
            cv_bridge::CvImage out;
            out.header.frame_id = image->header.frame_id;
            out.header.stamp = image->header.stamp;
            out.encoding = sensor_msgs::image_encodings::BGR8;
            out.image = mat;
            debug_pub_.publish(out.toImageMsg());
        }
    }

    // ── Map loading ───────────────────────────────────────────────────────────

    void loadMap(const std::string& filename)
    {
        clearMarkers();
        if (filename.empty()) {
            RCLCPP_INFO(this->get_logger(), "No map loaded");
            return;
        }

        std::ifstream f(filename);
        if (!f.good()) {
            RCLCPP_ERROR(this->get_logger(), "%s - %s", strerror(errno), filename.c_str());
            map_ = "";
            return;
        }

        std::string line;
        while (std::getline(f, line)) {
            int id;
            double length, x, y, z = 0, yaw = 0, pitch = 0, roll = 0;
            std::istringstream s(line);
            char first = 0;
            if (!(s >> first)) continue;
            if (first == '#') continue;
            if (std::isdigit(first)) s.putback(first);
            else { RCLCPP_ERROR(this->get_logger(), "Malformed input: %s", line.c_str()); continue; }
            if (!(s >> id >> length >> x >> y)) {
                RCLCPP_ERROR(this->get_logger(), "Not enough data: %s", line.c_str());
                continue;
            }
            s >> z; s >> yaw; s >> pitch; s >> roll;
            addMarker(id, length, x, y, z, yaw, pitch, roll);
        }

        RCLCPP_INFO(this->get_logger(), "loading %s complete (%d markers)",
                    filename.c_str(), static_cast<int>(board_->ids.size()));
    }

    void addMarker(int id, double length, double x, double y, double z,
                   double yaw, double pitch, double roll)
    {
        int num_markers = board_->dictionary->bytesList.rows;
        if (num_markers <= id) {
            RCLCPP_ERROR(this->get_logger(), "Marker id %d not in dictionary (size %d)", id, num_markers);
            return;
        }
        if (std::count(board_->ids.begin(), board_->ids.end(), id) > 0) {
            RCLCPP_ERROR(this->get_logger(), "Marker id %d already in map", id);
            return;
        }

        // Build marker corners using tf2 transform
        tf2::Quaternion q;
        q.setRPY(roll, pitch, yaw);
        tf2::Transform transform(q, tf2::Vector3(x, y, z));

        double halflen = length / 2;
        auto p0 = transform * tf2::Vector3(-halflen,  halflen, 0);
        auto p1 = transform * tf2::Vector3( halflen,  halflen, 0);
        auto p2 = transform * tf2::Vector3( halflen, -halflen, 0);
        auto p3 = transform * tf2::Vector3(-halflen, -halflen, 0);

        vector<cv::Point3f> obj_points = {
            cv::Point3f(p0.x(), p0.y(), p0.z()),
            cv::Point3f(p1.x(), p1.y(), p1.z()),
            cv::Point3f(p2.x(), p2.y(), p2.z()),
            cv::Point3f(p3.x(), p3.y(), p3.z())
        };

        board_->ids.push_back(id);
        board_->objPoints.push_back(obj_points);

        // Static transform for marker frame
        if (!markers_frame_.empty()) {
            geometry_msgs::msg::TransformStamped t;
            t.header.frame_id = markers_parent_frame_;
            t.child_frame_id = markers_frame_ + std::to_string(id);
            t.transform.translation.x = x;
            t.transform.translation.y = y;
            t.transform.translation.z = z;
            t.transform.rotation = tf2::toMsg(q);
            markers_transforms_.push_back(t);
        }

        // Marker msg
        aruco_pose::msg::Marker marker;
        marker.id = id;
        marker.length = length;
        marker.pose.position.x = x;
        marker.pose.position.y = y;
        marker.pose.position.z = z;
        marker.pose.orientation = tf2::toMsg(q);
        markers_.markers.push_back(marker);

        // Visualization
        visualization_msgs::msg::Marker vis;
        vis.header.frame_id = transform_.child_frame_id;
        vis.action = visualization_msgs::msg::Marker::ADD;
        vis.id = vis_array_.markers.size();
        vis.ns = "aruco_map_marker";
        vis.type = visualization_msgs::msg::Marker::CUBE;
        vis.scale.x = length; vis.scale.y = length; vis.scale.z = 0.001;
        vis.color.r = 1; vis.color.g = 0.5; vis.color.b = 0.5; vis.color.a = 0.8;
        vis.pose.position.x = x; vis.pose.position.y = y; vis.pose.position.z = z;
        vis.pose.orientation = tf2::toMsg(q);
        vis.frame_locked = true;
        vis_array_.markers.push_back(vis);
    }

    void clearMarkers()
    {
        board_->ids.clear();
        board_->objPoints.clear();
        markers_.markers.clear();
        vis_array_.markers.clear();
        markers_transforms_.clear();
    }

    void publishMap()
    {
        if (!markers_transforms_.empty()) static_br_.sendTransform(markers_transforms_);
        markers_pub_->publish(markers_);
        publishMapImage();
        vis_markers_pub_->publish(vis_array_);
    }

    void publishMapImage()
    {
        cv::Size size(image_width_, image_height_);
        cv::Mat image;
        cv_bridge::CvImage msg;

        if (!board_->ids.empty()) {
            _drawPlanarBoard(board_, size, image, image_margin_, 1, image_axis_);
            msg.encoding = image_axis_ ? sensor_msgs::image_encodings::RGB8 : sensor_msgs::image_encodings::MONO8;
        } else {
            image.create(size, CV_8UC1);
            image.setTo(cv::Scalar::all(255));
            msg.encoding = sensor_msgs::image_encodings::MONO8;
        }
        msg.image = image;
        img_pub_->publish(*msg.toImageMsg());
    }

    void createGridBoard()
    {
        RCLCPP_INFO(this->get_logger(), "generate gridboard");
        RCLCPP_WARN(this->get_logger(), "gridboard maps are deprecated");

        int markers_x = this->declare_parameter("markers_x", 10);
        int markers_y = this->declare_parameter("markers_y", 10);
        int first_marker = this->declare_parameter("first_marker", 0);
        double markers_side = this->declare_parameter("markers_side", 0.1);
        double markers_sep_x = this->declare_parameter("markers_sep_x", 0.02);
        double markers_sep_y = this->declare_parameter("markers_sep_y", 0.02);

        std::vector<int> marker_ids(markers_x * markers_y);
        for (int i = 0; i < markers_x * markers_y; i++) marker_ids[i] = first_marker++;

        double max_y = markers_y * markers_side + (markers_y - 1) * markers_sep_y;
        for (int y = 0; y < markers_y; y++) {
            for (int x = 0; x < markers_x; x++) {
                addMarker(marker_ids[y * markers_y + x],
                          markers_side,
                          x * (markers_side + markers_sep_x),
                          max_y - y * (markers_side + markers_sep_y) - markers_side,
                          0, 0, 0, 0);
            }
        }
    }

    void alignObjPointsToCenter(Mat& obj_points, double& cx, double& cy, double& cz) const
    {
        double sx = 0, sy = 0, sz = 0;
        for (int i = 0; i < obj_points.rows; i++) {
            sx += obj_points.at<float>(i, 0);
            sy += obj_points.at<float>(i, 1);
            sz += obj_points.at<float>(i, 2);
        }
        cx = sx / obj_points.rows;
        cy = sy / obj_points.rows;
        cz = sz / obj_points.rows;
        for (int i = 0; i < obj_points.rows; i++) {
            obj_points.at<float>(i, 0) -= cx;
            obj_points.at<float>(i, 1) -= cy;
            obj_points.at<float>(i, 2) -= cz;
        }
    }

    rcl_interfaces::msg::SetParametersResult paramCallback(
        const std::vector<rclcpp::Parameter>& params)
    {
        for (const auto& p : params) {
            if (p.get_name() == "enabled") {
                enabled_ = p.as_bool();
            } else if (p.get_name() == "map" && type_ == "map") {
                map_ = p.as_string();
                loadMap(map_);
                publishMap();
            } else if (p.get_name() == "image_axis") {
                image_axis_ = p.as_bool();
                publishMapImage();
            }
        }
        rcl_interfaces::msg::SetParametersResult result;
        result.successful = true;
        return result;
    }
};

int main(int argc, char** argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<ArucoMap>());
    rclcpp::shutdown();
    return 0;
}
