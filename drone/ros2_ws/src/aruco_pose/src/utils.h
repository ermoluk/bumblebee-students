/*
 * Utility functions (ROS2 Jazzy port)
 * Copyright (C) 2018 Copter Express Technologies
 * Author: Oleg Kalachev <okalachev@gmail.com>
 * Distributed under MIT License
 */

#pragma once

#include <cmath>
#include <rclcpp/rclcpp.hpp>
#include <tf2/LinearMath/Quaternion.h>
#include <tf2/LinearMath/Matrix3x3.h>
#include <tf2/LinearMath/Transform.h>
#include <tf2_geometry_msgs/tf2_geometry_msgs.hpp>
#include <geometry_msgs/msg/quaternion.hpp>
#include <geometry_msgs/msg/pose.hpp>
#include <geometry_msgs/msg/vector3.hpp>
#include <geometry_msgs/msg/transform.hpp>
#include <sensor_msgs/msg/camera_info.hpp>
#include <opencv2/opencv.hpp>

static void parseCameraInfo(const sensor_msgs::msg::CameraInfo::ConstSharedPtr& cinfo,
                            cv::Mat& matrix, cv::Mat& dist)
{
    for (unsigned int i = 0; i < 3; ++i)
        for (unsigned int j = 0; j < 3; ++j)
            matrix.at<double>(i, j) = cinfo->k[3 * i + j];
    dist = cv::Mat(cinfo->d, true);
}

inline void fillPose(geometry_msgs::msg::Pose& pose, const cv::Vec3d& rvec, const cv::Vec3d& tvec)
{
    pose.position.x = tvec[0];
    pose.position.y = tvec[1];
    pose.position.z = tvec[2];
    double angle = cv::norm(rvec);
    cv::Vec3d axis = rvec / angle;
    tf2::Quaternion q;
    q.setRotation(tf2::Vector3(axis[0], axis[1], axis[2]), angle);
    pose.orientation = tf2::toMsg(q);
}

inline void fillTransform(geometry_msgs::msg::Transform& transform,
                          const cv::Vec3d& rvec, const cv::Vec3d& tvec)
{
    transform.translation.x = tvec[0];
    transform.translation.y = tvec[1];
    transform.translation.z = tvec[2];
    double angle = cv::norm(rvec);
    cv::Vec3d axis = rvec / angle;
    tf2::Quaternion q;
    q.setRotation(tf2::Vector3(axis[0], axis[1], axis[2]), angle);
    transform.rotation = tf2::toMsg(q);
}

inline void fillTranslation(geometry_msgs::msg::Vector3& translation, const cv::Vec3d& tvec)
{
    translation.x = tvec[0];
    translation.y = tvec[1];
    translation.z = tvec[2];
}

inline bool isFlipped(const tf2::Quaternion& q)
{
    double yaw, pitch, roll;
    tf2::Matrix3x3(q).getEulerYPR(yaw, pitch, roll);
    return (std::abs(pitch) > M_PI / 2) || (std::abs(roll) > M_PI / 2);
}

inline void applyVertical(geometry_msgs::msg::Quaternion& orientation,
                          const geometry_msgs::msg::Quaternion& vertical,
                          bool flip_vertical = false, bool auto_flip = false)
{
    tf2::Quaternion _vertical, _orientation;
    tf2::fromMsg(vertical, _vertical);
    tf2::fromMsg(orientation, _orientation);
    if (flip_vertical || (auto_flip && !isFlipped(_orientation))) {
        tf2::Quaternion flip;
        flip.setRPY(M_PI, 0, 0);
        _vertical = _vertical * flip;
    }
    auto diff = tf2::Matrix3x3(_orientation).transposeTimes(tf2::Matrix3x3(_vertical));
    double yaw, pitch, roll;
    diff.getEulerYPR(yaw, pitch, roll);
    tf2::Quaternion q;
    q.setRPY(0, 0, -yaw);
    _vertical = _vertical * q;
    orientation = tf2::toMsg(_vertical);
}

inline void transformToPose(const geometry_msgs::msg::Transform& transform,
                            geometry_msgs::msg::Pose& pose)
{
    pose.position.x = transform.translation.x;
    pose.position.y = transform.translation.y;
    pose.position.z = transform.translation.z;
    pose.orientation = transform.rotation;
}
